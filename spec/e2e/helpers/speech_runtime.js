import { expect } from "@playwright/test"
import { runRails } from "./rails_runner.js"
import { TRANSCRIPT } from "./provider_backend.js"
import { waitForAssistantController, waitForAssistantStreams } from "./assistant_ui.js"

// Uses Chromium's real MediaRecorder and the normal upload/probe/job pipeline.
// The local HTTP service supplies only the vendor's transcription response.
export async function verifyRecordedTranscription(page, request, conversationId) {
  const button = page.locator("[data-speech-to-text-target='button']").first()
  await waitForAssistantController(page, "speech-to-text")
  await waitForAssistantStreams(page)
  await button.click()
  await expect(page.locator("[data-speech-to-text-target='status']").first()).toHaveText("Recording…")
  // Recording time is necessary audio data, not an initialization sleep. Read
  // the actual recorder state/elapsed duration without invoking app methods.
  await page.waitForFunction(() => {
    const mount = document.querySelector("[data-controller~='speech-to-text']")
    const controller = mount && window.Stimulus?.getControllerForElementAndIdentifier(mount, "speech-to-text")
    return controller?.recorder?.state === "recording" && Date.now() - controller.startedAt >= 1200
  })
  // Observe native recorder output before Stop. Chromium's network inspector
  // omits file bytes from multipart postDataBuffer; do not substitute fake audio.
  await page.evaluate(() => {
    const mount = document.querySelector("[data-controller~='speech-to-text']")
    const { recorder } = window.Stimulus.getControllerForElementAndIdentifier(mount, "speech-to-text")
    window.e2eRecordedAudio = new Promise(resolve => recorder.addEventListener("dataavailable", async event => {
      resolve(Array.from(new Uint8Array(await event.data.arrayBuffer())))
    }, { once: true }))
  })
  const accepted = page.waitForResponse(response => response.request().method() === "POST" && /\/transcriptions$/.test(new URL(response.url()).pathname))
  await button.click()
  const response = await accepted
  expect(response.status()).toBe(202)
  const { clip_id: clipId } = await response.json()
  expect(Number.isInteger(clipId)).toBe(true)
  await expect(page.locator("[data-role='user']").filter({ hasText: TRANSCRIPT })).toBeVisible({ timeout: 30000 })
  // Clip intentionally stores no duration column. Re-probe the captured native
  // recorder bytes with the real AudioProbe after the normal upload succeeds.
  const audio = Buffer.from(await page.evaluate(() => window.e2eRecordedAudio))
  expect(audio.length).toBeGreaterThan(0)
  const output = runRails(`
    require "base64"
    require "stringio"
    require "digest"
    audio = StringIO.new(Base64.decode64(${JSON.stringify(audio.toString("base64"))}))
    duration = SpeechToText::AudioProbe.call(upload: { io: audio }, max_duration: 10)
    abort "Recorded audio duration invalid" unless duration.positive? && duration < 10
    clip = SpeechToText::Clip.find(${clipId})
    abort "Audio pipeline did not succeed" unless clip.status == "succeeded"
    abort "Transcription was not pinned" unless clip.conversation_id == ${Number(conversationId)}
    abort "Transcription entered wrong conversation" unless clip.conversation.messages.where(role: "user", body: ${JSON.stringify(TRANSCRIPT)}).exists?
    abort "Audio was not purged" if clip.audio.attached?
    puts({ clip_id: clip.id, status: clip.status, decoded_duration: duration,
      conversation_id: clip.conversation_id, audio_purged: true,
      audio_bytes: audio.size, audio_sha256: Digest::SHA256.hexdigest(audio.string) }.to_json)
  `)
  const proof = JSON.parse(output.trim().split("\n").at(-1))
  const provider = new URL(process.env.E2E_PROVIDER_URL || "http://127.0.0.1:3012/v1")
  const health = await request.get(`${provider.origin}/health`)
  expect(health.ok()).toBe(true)
  expect((await health.json()).requests).toContainEqual({ path: "/v1/audio/transcriptions", audioBytes: proof.audio_bytes, audioSha256: proof.audio_sha256 })
  process.stdout.write(`Transcription proof: ${JSON.stringify(proof)}\n`)
}
