{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [

    # Process Monitoring
    btop

    # Network / I/O Monitoring
    iotop
    iftop

    # System Inspection
    lsof
    lm_sensors
    pciutils
    usbutils
  ];
}
