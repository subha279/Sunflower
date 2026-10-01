{ pkgs, ... }:

let
  vars = import ../../lib/variables.nix;
in

{
  # Virtualisation
  virtualisation.libvirtd = {
    enable = true;

    # Do not bring guests up while the machine is still booting.
    onBoot = "ignore";
    qemu = {
      package = pkgs.qemu_kvm;
      runAsRoot = true;
      swtpm.enable = true;

      # VirtIO-FS support
      vhostUserPackages = [
        pkgs.virtiofsd
      ];
    };
  };

  # Virt-Manager
  programs.virt-manager.enable = true;
  virtualisation.spiceUSBRedirection.enable = true;

  # User Access
  users.users.${vars.user.username}.extraGroups = [
    "libvirtd"
  ];
}
