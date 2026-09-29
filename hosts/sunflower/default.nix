{ ... }:

let
  vars = import ../../lib/variables.nix;
in
{
  imports = [
    ./hardware-configuration.nix
    ../../modules/core
    ../../modules/boot
    ../../modules/networking
    ../../modules/users
    ../../modules/packages
    ../../modules/fonts
    ../../modules/audio
    ../../modules/bluetooth
    ../../modules/polkit
    ../../modules/graphics
    ../../modules/xdg
    ../../modules/notifications
    ../../modules/hyprland
    ../../modules/desktop
    ../../modules/session
    ../../modules/monitoring
    ../../modules/nvidia
    ../../modules/power
    ../../modules/stylix
    ../../modules/development
    ../../modules/services/postgresql
    ../../modules/creator
    ../../modules/virtualisation
    ../../modules/hardware/kreo-rgb
  ];

  hardware.kreoRgb = {
    enable = true;
    followTheme = true;
  };

  networking.hostName = vars.system.hostname;
}
