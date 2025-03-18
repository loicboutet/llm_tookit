module LlmToolkit
  class Tool < ApplicationRecord
    validates :name, presence: true, uniqueness: true
    validates :description, presence: true
  end
end