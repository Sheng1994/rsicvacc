#!/usr/bin/env python3
"""Batch MNIST dashboard for the integrated CV32E40X + NN MicroZed design."""
import argparse, gzip, json, random, re, struct, subprocess, tempfile, threading, time, webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

ROOT = Path(__file__).resolve().parents[1]
IMAGES = ROOT / "data/mnist/t10k-images-idx3-ubyte.gz"
LABELS = ROOT / "data/mnist/t10k-labels-idx1-ubyte.gz"
REMOTE = "sheng@192.168.1.10"
REMOTE_ROOT = "/home/sheng/Work/rsicvacc"
FPGA_HZ = 20_000_000

def load_mnist():
    with gzip.open(IMAGES, "rb") as f:
        magic, count, rows, cols = struct.unpack(">IIII", f.read(16)); images = f.read()
    with gzip.open(LABELS, "rb") as f:
        lmagic, lcount = struct.unpack(">II", f.read(8)); labels = f.read()
    if (magic, rows, cols, lmagic, lcount, len(images)) != (2051, 28, 28, 2049, count, count*784):
        raise ValueError("invalid MNIST test dataset")
    return count, images, labels

COUNT, IMAGE_DATA, LABEL_DATA = load_mnist()

def image_words(index):
    pixels = IMAGE_DATA[index*784:(index+1)*784]
    q = [p >> 1 for p in pixels]
    return [sum((q[k+i] & 255) << (8*i) for i in range(4)) for k in range(0, 784, 4)]

RESULT_RE = re.compile(
    r"CODEX_BATCH_RESULT index=(\d+) label=(\d+) prediction=(\d+) correct=(\d+) "
    r"scores=([-\d,]+) macs=(\d+) cpu_cycles=(\d+) accel_cycles=(\d+) "
    r"total_cycles=(\d+) processed=(\d+) correct_total=(\d+) elapsed_ms=(\d+)")

class BatchRunner:
    def __init__(self):
        self.lock = threading.Lock(); self.state = self.empty()
    @staticmethod
    def empty():
        return {"running": False, "requested": 0, "processed": 0, "correct": 0,
                "results": [], "error": None, "started_at": None, "finished_at": None,
                "fpga_hz": FPGA_HZ, "power_w": None, "power_kind": "Vivado vectorless estimate"}
    def snapshot(self):
        with self.lock: return json.loads(json.dumps(self.state))
    def start(self, start, count, randomize, program):
        with self.lock:
            if self.state["running"]: raise RuntimeError("a batch is already running")
            indices = random.sample(range(COUNT), count) if randomize else [(start+i) % COUNT for i in range(count)]
            self.state = self.empty(); self.state.update(running=True, requested=count, started_at=time.time())
        jobs = [(idx, int(LABEL_DATA[idx]), bytes(IMAGE_DATA[idx*784:(idx+1)*784]), False) for idx in indices]
        threading.Thread(target=self._run, args=(jobs, program), daemon=True).start()
    def start_drawn(self, pixels, program):
        if len(pixels) != 784 or any(not isinstance(p, int) or p < 0 or p > 255 for p in pixels):
            raise ValueError("pixels must contain exactly 784 integers in the range 0..255")
        with self.lock:
            if self.state["running"]: raise RuntimeError("a batch is already running")
            self.state = self.empty(); self.state.update(running=True, requested=1, started_at=time.time())
        threading.Thread(target=self._run, args=([(10000, 255, bytes(pixels), True)], program), daemon=True).start()
    @staticmethod
    def _words(pixels):
        q = [p >> 1 for p in pixels]
        return [sum((q[k+i] & 255) << (8*i) for i in range(4)) for k in range(0, 784, 4)]
    def _run(self, jobs, program):
        try:
            with tempfile.TemporaryDirectory(prefix="riscv-mnist-batch-") as td:
                plan = Path(td)/"batch.txt"
                with plan.open("w") as f:
                    for idx, label, pixels, _ in jobs:
                        f.write(f"{idx} {label} " + " ".join(f"0x{x:08x}" for x in self._words(pixels)) + "\n")
                pixels_by_index = {idx: pixels for idx, _, pixels, _ in jobs}
                drawn_by_index = {idx: drawn for idx, _, _, drawn in jobs}
                remote_plan = f"/tmp/{plan.name}"
                subprocess.run(["scp","-q","-P","22",str(plan),f"{REMOTE}:{remote_plan}"], check=True)
                mode = " program" if program else ""
                cmd = (f"cd {REMOTE_ROOT} && export LD_LIBRARY_PATH=$HOME/Work/rsicvacc/.vivado-compat:${{LD_LIBRARY_PATH:-}} && "
                       f"/opt/AMD/2026.1/Vivado/bin/xsdb fpga/microzed/run_riscv_mnist_batch.tcl {remote_plan}{mode}")
                proc = subprocess.Popen(["ssh","-p","22","-o","BatchMode=yes",REMOTE,cmd], text=True,
                                        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, bufsize=1)
                tail = []
                for line in proc.stdout:
                    tail.append(line.rstrip()); tail = tail[-40:]
                    m = RESULT_RE.search(line)
                    if not m: continue
                    result = {"index":int(m[1]),"label":int(m[2]),"prediction":int(m[3]),"correct":bool(int(m[4])),
                              "scores":[int(x) for x in m[5].split(",")],"macs":int(m[6]),
                              "cpu_cycles":int(m[7]),"accel_cycles":int(m[8]),"total_cycles":int(m[9]),
                              "processed":int(m[10]),"correct_total":int(m[11]),"elapsed_ms":int(m[12]),
                              "pixels":list(pixels_by_index[int(m[1])]), "drawn":drawn_by_index[int(m[1])],
                              "label_known":not drawn_by_index[int(m[1])]}
                    result["inference_ms"] = 1000*result["total_cycles"]/FPGA_HZ
                    result["images_per_s"] = FPGA_HZ/result["total_cycles"] if result["total_cycles"] else 0
                    result["gmac_per_s"] = result["macs"]*result["images_per_s"]/1e9
                    with self.lock:
                        self.state["processed"] = result["processed"]; self.state["correct"] = result["correct_total"]
                        self.state["results"].append(result); self.state["results"] = self.state["results"][-200:]
                if proc.wait() != 0: raise RuntimeError("\n".join(tail[-20:]))
        except Exception as exc:
            with self.lock: self.state["error"] = str(exc)
        finally:
            with self.lock: self.state["running"] = False; self.state["finished_at"] = time.time()

RUNNER = BatchRunner()

HTML = r'''<!doctype html><html><head><meta charset="utf-8"><title>RISC-V NN MNIST</title>
<style>:root{color-scheme:dark}body{font-family:system-ui;margin:24px auto;max-width:1100px;padding:0 18px;background:#0d1117;color:#e6edf3}button,input{font:inherit;padding:8px;border:1px solid #46515f;border-radius:6px;background:#161b22;color:inherit}button{background:#238636;cursor:pointer}button.secondary{background:#30363d}.row{display:flex;gap:10px;flex-wrap:wrap;align-items:end}.tabs{display:flex;gap:8px;margin-bottom:14px}.tabs button.active{outline:2px solid #58a6ff}.cards{display:grid;grid-template-columns:repeat(4,1fr);gap:12px;margin:18px 0}.card,.panel{background:#161b22;border:1px solid #30363d;border-radius:10px;padding:14px}.value{font-size:25px}.layout{display:grid;grid-template-columns:300px 1fr;gap:16px}canvas{width:280px;height:280px;image-rendering:pixelated;background:#000;touch-action:none}.draw{border:1px solid #46515f;cursor:crosshair}.bar{height:24px;background:#21262d;margin:5px 0;position:relative}.fill{height:100%;background:#2f81f7}.bar span{position:absolute;left:7px;top:2px}.ok{color:#3fb950}.bad{color:#f85149}#trend{width:100%;height:180px}#batchPanel{display:none}@media(max-width:760px){.cards{grid-template-columns:1fr 1fr}.layout{grid-template-columns:1fr}}</style></head>
<body><h1>CV32E40X + NN MNIST</h1><div class="tabs"><button id="handTab" class="active">手写识别</button><button id="batchTab" class="secondary">数据集批量测试</button></div>
<div id="handPanel" class="row"><div><canvas id="draw" class="draw" width="280" height="280"></canvas><div class="row" style="margin-top:10px"><button id="recognize">上传到 FPGA 并识别</button><button id="clear" class="secondary">清空</button><label><input id="programHand" type="checkbox"> 重新下载 bitstream</label></div><small>请在黑色区域用鼠标或触控书写一个白色数字</small></div></div>
<div id="batchPanel" class="row"><label>起始样本<br><input id="start" type="number" min="0" max="9999" value="0"></label><label>数量<br><input id="count" type="number" min="1" max="10000" value="100"></label><label><input id="random" type="checkbox"> 随机抽样</label><label><input id="program" type="checkbox" checked> 重新下载 bitstream</label><button id="go">开始批量推理</button></div><p id="status">就绪</p>
<div class="cards"><div class="card">进度<div class="value" id="progress">0 / 0</div></div><div class="card">准确率<div class="value" id="accuracy">—</div></div><div class="card">硬件吞吐<div class="value" id="throughput">—</div></div><div class="card">推理延迟<div class="value" id="latency">—</div></div></div>
<div class="layout"><div class="panel"><canvas id="img" width="28" height="28"></canvas><h2 id="pred">等待样本</h2></div><div class="panel"><canvas id="trend" width="720" height="180"></canvas><div id="detail"></div><div id="bars"></div></div></div>
<script>let last=0,dc=draw.getContext('2d');dc.fillStyle='#000';dc.fillRect(0,0,280,280);dc.strokeStyle='#fff';dc.lineWidth=22;dc.lineCap=dc.lineJoin='round';let down=false,px=0,py=0;function pos(e){let r=draw.getBoundingClientRect(),p=e.touches?e.touches[0]:e;return [(p.clientX-r.left)*280/r.width,(p.clientY-r.top)*280/r.height]}function begin(e){e.preventDefault();down=true;[px,py]=pos(e);dc.beginPath();dc.moveTo(px,py);dc.lineTo(px+.01,py+.01);dc.stroke()}function move(e){if(!down)return;e.preventDefault();let [x,y]=pos(e);dc.beginPath();dc.moveTo(px,py);dc.lineTo(x,y);dc.stroke();px=x;py=y}function end(){down=false}draw.onpointerdown=begin;draw.onpointermove=move;draw.onpointerup=draw.onpointerleave=end;clear.onclick=()=>{dc.fillStyle='#000';dc.fillRect(0,0,280,280)};function mnistPixels(){let src=dc.getImageData(0,0,280,280).data,minx=280,miny=280,maxx=-1,maxy=-1;for(let y=0;y<280;y++)for(let x=0;x<280;x++)if(src[(y*280+x)*4]>8){minx=Math.min(minx,x);maxx=Math.max(maxx,x);miny=Math.min(miny,y);maxy=Math.max(maxy,y)}if(maxx<0)throw Error('请先写一个数字');let w=maxx-minx+1,h=maxy-miny+1,s=20/Math.max(w,h),tw=Math.max(1,Math.round(w*s)),th=Math.max(1,Math.round(h*s)),tmp=document.createElement('canvas');tmp.width=28;tmp.height=28;let t=tmp.getContext('2d');t.fillStyle='#000';t.fillRect(0,0,28,28);t.imageSmoothingEnabled=true;t.drawImage(draw,minx,miny,w,h,Math.floor((28-tw)/2),Math.floor((28-th)/2),tw,th);let a=t.getImageData(0,0,28,28).data,mx=0,my=0,sum=0;for(let y=0;y<28;y++)for(let x=0;x<28;x++){let v=a[(y*28+x)*4];sum+=v;mx+=x*v;my+=y*v}if(sum){let sx=Math.round(13.5-mx/sum),sy=Math.round(13.5-my/sum),b=document.createElement('canvas');b.width=b.height=28;let q=b.getContext('2d');q.fillStyle='#000';q.fillRect(0,0,28,28);q.drawImage(tmp,sx,sy);a=q.getImageData(0,0,28,28).data}return Array.from({length:784},(_,i)=>a[i*4])}recognize.onclick=async()=>{try{let r=await fetch('/api/draw',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({pixels:mnistPixels(),program:programHand.checked})}),d=await r.json();if(!r.ok)throw Error(d.error)}catch(e){alert(e.message)}};handTab.onclick=()=>{handPanel.style.display='flex';batchPanel.style.display='none';handTab.className='active';batchTab.className='secondary'};batchTab.onclick=()=>{handPanel.style.display='none';batchPanel.style.display='flex';handTab.className='secondary';batchTab.className='active'};go.onclick=async()=>{let q=new URLSearchParams({start:start.value,count:count.value,random:random.checked?1:0,program:program.checked?1:0});let r=await fetch('/api/start?'+q),d=await r.json();if(!r.ok)alert(d.error)};function drawTrend(rs){let c=trend.getContext('2d'),w=trend.width,h=trend.height;c.clearRect(0,0,w,h);c.strokeStyle='#30363d';for(let y=20;y<h;y+=40){c.beginPath();c.moveTo(0,y);c.lineTo(w,y);c.stroke()}if(rs.length<2)return;let vals=rs.map(x=>x.images_per_s),lo=Math.min(...vals),hi=Math.max(...vals);c.strokeStyle='#2f81f7';c.lineWidth=2;c.beginPath();vals.forEach((v,i)=>{let x=i*w/(vals.length-1),y=h-10-(v-lo)/(hi-lo||1)*(h-20);i?c.lineTo(x,y):c.moveTo(x,y)});c.stroke()}async function poll(){let d=await(await fetch('/api/status')).json();progress.textContent=d.processed+' / '+d.requested;accuracy.textContent=d.processed&&!d.results.at(-1)?.drawn?(100*d.correct/d.processed).toFixed(2)+'%':'—';status.textContent=d.error?'错误：'+d.error:(d.running?'FPGA 正在运行…':'就绪');go.disabled=recognize.disabled=d.running;let x=d.results.at(-1);if(x){throughput.textContent=x.images_per_s.toFixed(1)+' img/s';latency.textContent=x.inference_ms.toFixed(3)+' ms';let c=img.getContext('2d'),im=c.createImageData(28,28);x.pixels.forEach((p,i)=>{im.data[i*4]=im.data[i*4+1]=im.data[i*4+2]=p;im.data[i*4+3]=255});c.putImageData(im,0,0);pred.className=x.label_known?(x.correct?'ok':'bad'):'ok';pred.textContent=x.label_known?`预测 ${x.prediction} / 标签 ${x.label}`:`FPGA 预测：${x.prediction}`;detail.textContent=`${x.drawn?'手写输入':'样本 '+x.index} · ${x.macs.toLocaleString()} MAC · 总周期 ${x.total_cycles.toLocaleString()} · CPU ${x.cpu_cycles.toLocaleString()} · NN ${x.accel_cycles.toLocaleString()} · ${x.gmac_per_s.toFixed(4)} GMAC/s · 功耗：未接入实时传感器`;let lo=Math.min(...x.scores),hi=Math.max(...x.scores);bars.innerHTML=x.scores.map((s,i)=>`<div class="bar"><div class="fill" style="width:${5+95*(s-lo)/(hi-lo||1)}%"></div><span>${i}: ${s}</span></div>`).join('');drawTrend(d.results)}setTimeout(poll,500)}poll();</script></body></html>'''

class Handler(BaseHTTPRequestHandler):
    def reply(self, code, value, kind="application/json"):
        body = value.encode() if isinstance(value,str) else json.dumps(value).encode(); self.send_response(code)
        self.send_header("Content-Type",kind+"; charset=utf-8"); self.send_header("Content-Length",str(len(body))); self.end_headers(); self.wfile.write(body)
    def do_GET(self):
        p=urlparse(self.path); q=parse_qs(p.query)
        try:
            if p.path=="/": return self.reply(200,HTML,"text/html")
            if p.path=="/api/status": return self.reply(200,RUNNER.snapshot())
            if p.path=="/api/start":
                RUNNER.start(int(q.get("start",[0])[0]),min(COUNT,max(1,int(q.get("count",[100])[0]))),q.get("random",["0"])[0]=="1",q.get("program",["1"])[0]=="1")
                return self.reply(200,{"started":True})
            return self.reply(404,{"error":"not found"})
        except Exception as exc: return self.reply(400,{"error":str(exc)})
    def do_POST(self):
        try:
            if urlparse(self.path).path != "/api/draw": return self.reply(404,{"error":"not found"})
            length = int(self.headers.get("Content-Length", "0"))
            if length <= 0 or length > 20000: raise ValueError("invalid request size")
            data = json.loads(self.rfile.read(length))
            RUNNER.start_drawn(data.get("pixels", []), bool(data.get("program", False)))
            return self.reply(200,{"started":True})
        except Exception as exc: return self.reply(400,{"error":str(exc)})
    def log_message(self, fmt,*args): pass

if __name__=="__main__":
    ap=argparse.ArgumentParser(); ap.add_argument("--host",default="127.0.0.1"); ap.add_argument("--port",type=int,default=8765); ap.add_argument("--no-browser",action="store_true"); args=ap.parse_args()
    url=f"http://{args.host}:{args.port}/"; print(url)
    if not args.no_browser: webbrowser.open(url)
    ThreadingHTTPServer((args.host,args.port),Handler).serve_forever()
