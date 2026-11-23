---
title: "Turn an assistant request into reviewed work"
summary: "Give clear context, inspect what was saved or proposed, and verify changes before sharing the result."
---

## Before you start

Sign in as an administrator and open **AI Assistant**. Chat requires the assistant module and a ready generation service. Dictation also needs an available audio transcription service and microphone permission. If either is unavailable, ask support to check your organization's setup.

Under **Settings → AI assistant**, choose the speech-recognition language and select **Save changes**. **Auto** detects the language. Review the recording duration limit, which is managed for you. Website requests also require Website to be enabled.

## Steps

### Ask a focused question or request

1. Open a chat, or select **New chat** when you want a separate conversation. An empty current chat must receive a message before another new one can be started.
2. Describe one task with the relevant names and desired result. For example: “Create a Student record type with name, email, and enrollment date.” For website copy, try: “Draft an About page for our bakery with our opening hours and contact details.”
3. Type `@` to select an available record type when discussing an existing one. State the exact change rather than relying on an ambiguous name.
4. Review the request before sending. State the intended page or record type and the result you will check.

### Add images or dictate a request

1. Attach relevant images if the service supports them, such as an approved product photo for a website draft. Use at most eight images, 5 MB each and 20 MB total; remove unintended attachments.
2. For dictation, select the intended chat before pressing **Dictate**, allow microphone access, and stay within the displayed duration limit.
3. **Stop recording** uploads the clip. Successful assistant transcription is submitted to the chat selected when recording began; switching chats after upload does not send the recording to the newly selected chat. Review the resulting turn and follow up in the original chat if a correction is needed.
4. For typed messages, press **Enter** to send, or **Shift + Enter** for a new line.
5. Wait for the response and read its result summary. Use **Stop** to interrupt a reply or **Try again** when appropriate; check whether anything was already saved before repeating a creation request.

### Review saved results and proposed updates

:::note
Creation requests can save content immediately. A proposed update explicitly marked “Nothing is saved yet” waits for **Apply changes**. Generated website pages remain drafts. Read the result summary to determine which action occurred; a preview alone is not proof of saving or publication.
:::

1. When a **Proposed changes** card appears, review every listed change and any notice about existing entries. Select **Apply changes** only when it matches your intention, or describe what should be adjusted.
2. After applying an update, check the result summary and reopen the named record type or content to verify the intended change. For example, confirm the proposed enrollment-date field appears where expected.
3. Check **Preview** for generated content. For website pages, open the Website editor, verify copy and images, then save and follow [website publishing](websites) before sharing.
4. A website reply may offer **Undo**. Read its confirmation: it deletes pages created by that reply and restores pages it revised, provided they have not since been edited or published. It is not a general recovery action for all assistant work.

### Organize chats

1. Use the conversation actions to rename a chat by its task, such as `About page review`.
2. Archive a finished conversation, or unarchive it to continue. Check that it appears in the intended list.
3. Delete a conversation only when its history is no longer needed. Deleting chat history does not reverse saved workspace changes.

## What to expect

Chats belong to your signed-in user within your organization. Another administrator does not automatically share your chat history. Supplied shared definitions and layouts retain their managed restrictions; ask support for changes outside the available customer actions.

## Troubleshooting

- **Chat is unavailable:** ask support to check module and service readiness.
- **Recording fails:** allow microphone access and stay within the displayed duration limit.
- **The chat limit is reached:** start a new chat; delete an unneeded chat if the conversation-count limit is reached.
- **A reply fails or connection drops:** reload and check the latest result before repeating a creation request.

## Related guides

- [Records](records)
- [Websites](websites)
- [Settings](settings)
- [Support](support)
