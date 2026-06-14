cask "kanvas" do
  version "0.1.0"
  sha256 "8781a0c7fbe1329752375757aaefa3c249aa235ed30a4d22279ffb88f0ba1348"

  url "https://github.com/s-age/kanvas/releases/download/v#{version}/Kanvas-#{version}.dmg"
  name "Kanvas"
  desc "Kanban-first task manager with drill-down canvas and Markdown editor"
  homepage "https://github.com/s-age/kanvas"

  depends_on macos: :sequoia

  app "Kanvas.app"

  zap trash: [
    "~/Library/Application Support/Kanvas",
    "~/Library/Preferences/com.kanvas.app.plist",
    "~/Library/Preferences/Kanvas.plist",
  ]
end
