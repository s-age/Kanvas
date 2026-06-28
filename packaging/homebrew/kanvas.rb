cask "kanvas" do
  version "0.1.1"
  sha256 "30fca9df5c2b41c180a7ee2268eca2d9e817f71967e48641b5e2049d2fc87f09"

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
