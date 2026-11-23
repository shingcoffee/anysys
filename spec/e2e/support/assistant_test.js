import { test as base } from "@playwright/test"
import { randomUUID } from "node:crypto"
import { runRails } from "../helpers/rails_runner.js"

// Mutation tests pin their own thread; four workers never share current_for.
// Fixture ownership is kept in the closure, so cleanup cannot remove another
// worker's entities or pre-existing seeded conversations.
export const isolatedAssistantTest = base.extend({
  assistantThread: async ({}, use, testInfo) => {
    const entityName = `PwC${randomUUID().replaceAll("-", "").slice(0, 16)}`
    const title = `E2E ${testInfo.project.name} w${testInfo.parallelIndex} ${entityName}`
    const result = runRails(`
      customer = Customer.find(81721200)
      owner = customer.users.find_by!(email: "lingercoffee@gmail.com")
      abort "Pinned owner required" unless owner.platform_owner?
      EntityDomain.find_by_name(customer.id, "Academics") || EntityDomain.create!(customer: customer, name: "Academics", color: "blue")
      conversation = AiAssistant::Conversation.start_for(customer: customer, user: owner)
      abort "Assistant conversation limit reached" unless conversation
      conversation.update!(title: ${JSON.stringify(title)})
      puts({ id: conversation.id }.to_json)
    `)
    const { id } = JSON.parse(result.trim().split("\n").at(-1))
    try {
      await use({ id, entityName, path: `/81721200/admin/assistant?conversation=${id}` })
    } finally {
      runRails(`
        customer = Customer.find(81721200)
        owner = customer.users.find_by!(email: "lingercoffee@gmail.com")
        Current.with_customer(customer) do
          Entity.where(customer: customer, name: ${JSON.stringify(entityName)}).find_each(&:destroy!)
          AiAssistant::Conversation.owned_by(customer: customer, user: owner)
            .find_by(id: ${id}, title: ${JSON.stringify(title)})&.destroy!
        end
      `)
    }
  }
})
