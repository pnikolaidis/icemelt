cask "icemelt" do
  version "0.12.0-melt.3"
  sha256 "0d05a6d063897f9225d37c82fa74c0c25d4d6d551e6e824bf4e89cbcdd42ced9"

  url "https://github.com/pnikolaidis/icemelt/releases/download/v#{version}/IceMelt-#{version}.dmg"
  name "IceMelt"
  desc "Menu bar manager, fork of Ice"
  homepage "https://github.com/pnikolaidis/icemelt"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  # ">= :tahoe" (not the bare symbol the style cop suggests): IceMelt
  # supports macOS 26 and later, not Tahoe exclusively.
  depends_on macos: ">= :tahoe"

  app "IceMelt.app"

  uninstall quit: "com.pnikolaidis.icemelt"

  zap trash: [
    "~/Library/HTTPStorages/com.pnikolaidis.icemelt",
    "~/Library/Preferences/com.pnikolaidis.icemelt.plist",
  ]
end
