---
title: NEON
date: 2020-04-09 10:35:14
tags:
- NEON
- SIMD
- vector
- intrinsic
categories: Performance
---

整理一下以前使用过的ARM NEON.

<!-- more -->

## 1. NEON简介
- NEON是ARM处理器提供的**高级SIMD**(Single Instruction, Multiple Data)扩展, 用于多媒体/深度学习框架等方面的硬件加速.

- 查看ARM处理器是否支持NEON 

```shell
$ cat /proc/cpuinfo
```
**ARMv7**处理器会显示**neon**

**ARMv8**处理器会显示**asimd**

如下是Cortex-A57处理器显示的信息
```shell
processor	: 0
BogoMIPS	: 125.00
Features	: fp asimd evtstrm aes pmull sha1 sha2 crc32 cpuid
CPU implementer	: 0x41
CPU architecture: 8
CPU variant	: 0x1
CPU part	: 0xd07
CPU revision	: 0
```

## 2. NEON寄存器

NEON寄存器可用于:
- 存储**浮点数**操作数(浮点数指令)
- 存储**标量**和**矢量**操作数(NEON指令)

**ARMv7-A和ARMv8-A的aarch32**, 有16个128bit的NEON寄存器(q0\~q15), 对应32个d0\~d31, q0对应d0和d1, q1对应d2和d3, 依次类推.

**ARMv8-A的aarch64**, 有32个128bit的NEON寄存器(v0\~v31), 对应32个d0\~d31, v0对应d0, v1对应d1, 依次类推.

下面从三个操作数角度认识NEON寄存器(**ARMv8-A的aarch64**)

### 2.1 浮点数

![](http://ww1.sinaimg.cn/large/006CVPwLly1g2gdtcwpsfj30ot0gkwfd.jpg)

浮点器寄存器分3类
- 32个**半精度**寄存器: h0~h31
- 32个**单精度**寄存器: s0~s31
- 32个**双精度**寄存器: d0~d31

浮点数寄存器可以直接用s0, d0等访问.

### 2.2 标量
![](http://ww1.sinaimg.cn/large/006CVPwLly1g2gdvvzwvaj30od0l5jso.jpg)

标量就是矢量中的**单个值**, 用下标来访问, 如v0.s[0]

### 2.3 矢量
NEON寄存器用于矢量时, 将16字节的NEON寄存器平均划分成若干个**lane**, 每个lane有相同类型/大小的**element**. 如v0.8h, 表示分成8个lane, 每个lane是两字节大小.

![](http://ww1.sinaimg.cn/large/006CVPwLly1g2gdxbjsvej30un0ez0tt.jpg)

这类似于车道, 车道越多, 单位时间内通行的车辆越多. 
![undefined](http://ww1.sinaimg.cn/large/005Kyrj9ly1gdmely2zbij30ms0g5ad4.jpg)


## 3. NEON编程
NEON编程有如下几种方式
- NEON intrinsic
- NEON asm

### 3.1 NEON intrinsic
- [NEON intrinsic](https://developer.arm.com/architectures/instruction-sets/simd-isas/neon/intrinsics)是ARM提供的一套NEON APIs, 介于ARM汇编和C/C++之间的一套接口. 使用它可以快速地使用NEON进行优化, **编译器**负责具体寄存器分配等底层操作, 可移植性较好. 一般推荐使用此种方法来实现相关优化.

- 头文件
  ```cpp
  #include <arm_neon.h>
  ```
  
### 3.2 NEON asm
NEON汇编需要开发者手动编写NEON指令, 完成指定的功能, 开发难度较大. 性能一般较优, 但可移植性差, 不同处理器可能使用的指令不同.

### 3.3 demo
以dotProduct为例, 对比下NEON的带来的性能提升.

#### 3.3.1 测试环境
- Linux ubuntu18arm64 4.15.0-76-generic #86-Ubuntu SMP Fri Jan 17 17:25:58 UTC 2020 aarch64 aarch64 aarch64 GNU/Linux
- gcc version 7.4.0 (Ubuntu/Linaro 7.4.0-1ubuntu1~18.04.1)
- C++11
- CMake **Release build版本**(默认打开-O3选项)

#### 3.3.2 测试源码

**CPP版本**
```cpp
float CPP::dotProduct(const std::vector<float> &v1,
                      const std::vector<float> &v2) {
  size_t size = v1.size();
  float mac = 0.0;

  for (size_t i = 0; i < size; i++) {
    mac += v1[i] * v2[i];
  }

  return mac;
}
```

对应ARM汇编如下
```asm
00000000000030e0 <_ZN3CPP10dotProductERKSt6vectorIfSaIfEES4_>:
    30e0:       a9400423        ldp     x3, x1, [x1]
    30e4:       cb030021        sub     x1, x1, x3
    30e8:       9342fc21        asr     x1, x1, #2
    30ec:       b4000181        cbz     x1, 311c <_ZN3CPP10dotProductERKSt6vectorIfSaIfEES4_+0x3c>
    30f0:       0f000400        movi    v0.2s, #0x0
    30f4:       f9400042        ldr     x2, [x2]
    30f8:       d2800000        mov     x0, #0x0                        // #0
    30fc:       d503201f        nop
    3100:       bc607862        ldr     s2, [x3, x0, lsl #2]
    3104:       bc607841        ldr     s1, [x2, x0, lsl #2]
    3108:       91000400        add     x0, x0, #0x1
    310c:       eb01001f        cmp     x0, x1
    3110:       1f010040        fmadd   s0, s2, s1, s0
    3114:       54ffff61        b.ne    3100 <_ZN3CPP10dotProductERKSt6vectorIfSaIfEES4_+0x20>  // b.any
    3118:       d65f03c0        ret
    311c:       0f000400        movi    v0.2s, #0x0
    3120:       d65f03c0        ret
    3124:       d503201f        nop
```


**NEON版本(intrinsic)**
```cpp
#if defined (__aarch64__)
float NEONIntrinsic::dotProduct(const std::vector<float> &v1,
                                const std::vector<float> &v2) {
  float mac = 0;
  size_t size = v1.size();
  float32x4_t v = vdupq_n_f32(0);

  size_t counter = size / 4;
  size_t idx = 0;
  for (size_t i = 0; i < counter; i++) {
    idx = i << 2;
    v = vmlaq_f32(v, vld1q_f32(&v1[idx]), vld1q_f32(&v2[idx]));
  }

  mac += vgetq_lane_f32(v, 0);
  mac += vgetq_lane_f32(v, 1);
  mac += vgetq_lane_f32(v, 2);
  mac += vgetq_lane_f32(v, 3);

  size_t leftover = size % 4;
  for(size_t i = size - leftover; i < size; i++) {
    mac += v1[i] * v2[i];
  }

  return mac;
}
#endif
```

对应ARM汇编如下
```asm
0000000000003260 <_ZN13NEONIntrinsic10dotProductERKSt6vectorIfSaIfEES4_>:
    3260:       a9400c24        ldp     x4, x3, [x1] 
    3264:       cb040063        sub     x3, x3, x4
    3268:       9342fc63        asr     x3, x3, #2
    326c:       d342fc65        lsr     x5, x3, #2
    3270:       b40003e5        cbz     x5, 32ec <_ZN13NEONIntrinsic10dotProductERKSt6vectorIfSaIfEES4_+0x8c>
    3274:       4f000401        movi    v1.4s, #0x0 
    3278:       f9400046        ldr     x6, [x2] 
    327c:       d2800000        mov     x0, #0x0                        // #0
    3280:       d37cec01        lsl     x1, x0, #4
    3284:       91000400        add     x0, x0, #0x1 
    3288:       eb0000bf        cmp     x5, x0
    328c:       3ce16882        ldr     q2, [x4, x1]
    3290:       3ce168c0        ldr     q0, [x6, x1]
    3294:       4e20cc41        fmla    v1.4s, v2.4s, v0.4s
    3298:       54ffff41        b.ne    3280 <_ZN13NEONIntrinsic10dotProductERKSt6vectorIfSaIfEES4_+0x20>  // b.any
    329c:       5e140423        mov     s3, v1.s[2]
    32a0:       5e1c0422        mov     s2, v1.s[3]
    32a4:       5e0c0424        mov     s4, v1.s[1]
    32a8:       0f000400        movi    v0.2s, #0x0 
    32ac:       927ef460        and     x0, x3, #0xfffffffffffffffc
    32b0:       eb03001f        cmp     x0, x3
    32b4:       1e202821        fadd    s1, s1, s0
    32b8:       1e242820        fadd    s0, s1, s4
    32bc:       1e232800        fadd    s0, s0, s3
    32c0:       1e222800        fadd    s0, s0, s2
    32c4:       54000122        b.cs    32e8 <_ZN13NEONIntrinsic10dotProductERKSt6vectorIfSaIfEES4_+0x88>  // b.hs, b.nlast
    32c8:       f9400041        ldr     x1, [x2] 
    32cc:       d503201f        nop
    32d0:       bc607882        ldr     s2, [x4, x0, lsl #2]
    32d4:       bc607821        ldr     s1, [x1, x0, lsl #2]
    32d8:       91000400        add     x0, x0, #0x1 
    32dc:       eb03001f        cmp     x0, x3
    32e0:       1f010040        fmadd   s0, s2, s1, s0
    32e4:       54ffff61        b.ne    32d0 <_ZN13NEONIntrinsic10dotProductERKSt6vectorIfSaIfEES4_+0x70>  // b.any
    32e8:       d65f03c0        ret
    32ec:       0f000401        movi    v1.2s, #0x0 
    32f0:       1e204024        fmov    s4, s1
    32f4:       1e204022        fmov    s2, s1
    32f8:       1e204023        fmov    s3, s1
    32fc:       17ffffeb        b       32a8 <_ZN13NEONIntrinsic10dotProductERKSt6vectorIfSaIfEES4_+0x48>
```

相关的NEON指令代码如下
```asm
    ... ...
    3280:       d37cec01        lsl     x1, x0, #4
    3284:       91000400        add     x0, x0, #0x1 
    3288:       eb0000bf        cmp     x5, x0
    328c:       3ce16882        ldr     q2, [x4, x1]
    3290:       3ce168c0        ldr     q0, [x6, x1]
    3294:       4e20cc41        fmla    v1.4s, v2.4s, v0.4s
    3298:       54ffff41        b.ne    3280 <_ZN13NEONIntrinsic10dotProductERKSt6vectorIfSaIfEES4_+0x20>  // b.any
    ... ...
```

#### 3.3.3 测试结果
在Release版本下, NEON版本相对于CPP版本, 性能提升大约12%左右

```shell
size = 256
mac = 980620160.000000  CPP took 582 ms
mac = 980620160.000000  OpenMP took 5305 ms
mac = 980620160.000000  NEONIntrinsic took 491 ms

size = 512
mac = 1855130752.000000  CPP took 1151 ms
mac = 1855130752.000000  OpenMP took 5728 ms
mac = 1855130752.000000  NEONIntrinsic took 1020 ms

size = 1024
mac = 3737227520.000000  CPP took 2297 ms
mac = 3737227520.000000  OpenMP took 5760 ms
mac = 3737227520.000000  NEONIntrinsic took 2032 ms

size = 2048
mac = 7566683136.000000  CPP took 4562 ms
mac = 7566683136.000000  OpenMP took 6511 ms
mac = 7566683136.000000  NEONIntrinsic took 3998 ms

size = 4096
mac = 15045939200.000000  CPP took 9138 ms
mac = 15045939200.000000  OpenMP took 7859 ms
mac = 15045939200.000000  NEONIntrinsic took 8105 ms
```

---

![程序员自我修养](http://ww1.sinaimg.cn/large/005Kyrj9ly1gbvsonijdoj3076076wex.jpg)

<center>
程序员自我修养(ID: dumphex)
</center>

---
