import unittest

class FCReferenceTest(unittest.TestCase):
    def test_fc16x4_expected(self):
        x=[12,-7,3,25,-16,8,4,-2,19,-11,6,1,-5,14,-9,7]
        w=[[2,-1,3,1,-2,2,0,1,-1,2,1,-3,2,1,-2,3],[-3,2,1,-1,2,-2,3,1,2,-1,2,1,-2,3,1,-1],[1,1,-2,3,1,0,-1,2,3,1,-3,2,1,-2,2,1],[2,-3,2,-2,1,3,1,-1,0,2,-1,3,-3,1,2,-2]]
        bias=[10,-20,5,0]
        accum=[sum(a*b for a,b in zip(x,row))+b for row,b in zip(w,bias)]
        def requant(v):
            q=(abs(v)+4)>>3
            q=-q if v<0 else q
            return max(-128,min(127,q))
        self.assertEqual(accum,[126,-32,41,-13])
        self.assertEqual([requant(v) for v in accum],[16,-4,5,-2])
