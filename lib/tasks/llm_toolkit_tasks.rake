# desc "Explaining what the task does"
# task :llm_toolkit do
#   # Task goes here
# end

namespace :llm_toolkit do
  desc "Copy migrations from LlmToolkit to application"
  task :install_migrations do
    Rails::Command.invoke :railties, ["install:migrations", "FROM=llm_toolkit"]
  end
end