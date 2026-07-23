ssh -p 22 -o BatchMode=yes sheng@192.168.1.10 \
'cd ~/Work/rsicvacc &&
export LD_LIBRARY_PATH="$HOME/Work/rsicvacc/.vivado-compat:${LD_LIBRARY_PATH:-}" &&
pgrep -x hw_server >/dev/null ||
nohup /opt/AMD/2026.1/Vivado/bin/hw_server -s tcp::3121 >/tmp/hw_server.log 2>&1 &'

cd ~/Downloads/rsicvacc
python3 scripts/mnist_fpga_gui.py --port 8766