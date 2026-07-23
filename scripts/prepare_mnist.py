#!/usr/bin/env python3
import argparse, gzip, struct
from pathlib import Path
import numpy as np

def idx_images(path):
    with gzip.open(path,'rb') as f:
        magic,n,rows,cols=struct.unpack('>IIII',f.read(16)); assert magic==2051
        return np.frombuffer(f.read(),dtype=np.uint8).reshape(n,rows*cols)
def idx_labels(path):
    with gzip.open(path,'rb') as f:
        magic,n=struct.unpack('>II',f.read(8)); assert magic==2049
        return np.frombuffer(f.read(),dtype=np.uint8)
def words_memh(data):
    data=bytes(data); data+=bytes((-len(data))%4)
    return '\n'.join(f'{int.from_bytes(data[i:i+4],"little"):08x}' for i in range(0,len(data),4))+'\n'

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--data',default='data/mnist');ap.add_argument('--out',default='build/mnist')
    ap.add_argument('--epochs',type=int,default=18);ap.add_argument('--seed',type=int,default=7);a=ap.parse_args()
    d=Path(a.data);o=Path(a.out);o.mkdir(parents=True,exist_ok=True)
    xtr=idx_images(d/'train-images-idx3-ubyte.gz').astype(np.float32)/255.0
    ytr=idx_labels(d/'train-labels-idx1-ubyte.gz');xte_u8=idx_images(d/'t10k-images-idx3-ubyte.gz');yte=idx_labels(d/'t10k-labels-idx1-ubyte.gz')
    rng=np.random.default_rng(a.seed);w=np.zeros((10,784),np.float32);b=np.zeros(10,np.float32)
    for epoch in range(a.epochs):
        order=rng.permutation(len(xtr));lr=0.35*(0.90**epoch)
        for begin in range(0,len(order),512):
            ids=order[begin:begin+512];x=xtr[ids];logits=x@w.T+b;logits-=logits.max(1,keepdims=True)
            p=np.exp(logits);p/=p.sum(1,keepdims=True);p[np.arange(len(ids)),ytr[ids]]-=1
            w-=lr*(p.T@x/len(ids)+1e-4*w);b-=lr*p.mean(0)
    scale=127.0/max(float(np.max(np.abs(w))),1e-9);qw=np.clip(np.rint(w*scale),-127,127).astype(np.int8)
    qb=np.rint(b*127.0*scale).astype(np.int32);qx=(xte_u8>>1).astype(np.int8)
    scores=qx.astype(np.int32)@qw.astype(np.int32).T+qb
    pred=scores.argmax(1);acc=float(np.mean(pred==yte));correct=np.flatnonzero(pred==yte);sample=int(correct[0])
    (o/'weights.memh').write_text(words_memh(qw.tobytes()),encoding='ascii')
    (o/'bias.memh').write_text(words_memh(qb.astype('<i4').tobytes()),encoding='ascii')
    (o/'sample.memh').write_text(words_memh(qx[sample].tobytes()),encoding='ascii')
    (o/'expected.txt').write_text(f'index={sample}\nlabel={int(yte[sample])}\nprediction={int(pred[sample])}\naccuracy={acc:.6f}\n',encoding='ascii')
    np.savez(o/'model.npz',weights=qw,bias=qb,sample=qx[sample],label=yte[sample],accuracy=acc)
    print(f'PASS: MNIST INT8 linear model accuracy={acc*100:.2f}% sample={sample} label={yte[sample]}')
if __name__=='__main__':main()
