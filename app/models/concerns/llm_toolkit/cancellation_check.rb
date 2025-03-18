module LlmToolkit
  module CancellationCheck
    extend ActiveSupport::Concern

    def with_cancellation_check(conversation)
      check_cancellation!(conversation)
      result = yield
      check_cancellation!(conversation)
      result
    end

    def check_cancellation!(conversation)
      return unless conversation
      raise "Conversation was canceled" if conversation.canceled?
    end
  end
end