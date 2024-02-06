#!/bin/bash
sudo apt update -y && sudo apt upgrade -y && sudo apt install -y flatpak &&
sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo &&
sudo flatpak install flathub com.geekbench.Geekbench6 &&
sudo flatpak run com.geekbench.Geekbench6