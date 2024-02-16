#!/bin/bash
sudo apt update -y && sudo apt upgrade -y && sudo apt install -y flatpak &&
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo &&
flatpak install flathub com.geekbench.Geekbench6 &&
flatpak run com.geekbench.Geekbench6
