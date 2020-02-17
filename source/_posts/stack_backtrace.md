---
title: 函数调用栈帧回溯
date: 2020-02-17 11:00:00
modified: 2020-02-17 11:00:00
tags:
- arm64
- stack
- backtrace
categories: Linux
---

本文以**arm64平台**上的测试程序为例，讲解函数调用的栈帧回溯基本原理
<!-- more -->

# 1. Overview
相关的函数调用规范，可参考arm官方的[aapcs64文档](https://developer.arm.com/docs/ihi0055/d/procedure-call-standard-for-the-arm-64-bit-architecture)

![undefined](http://ww1.sinaimg.cn/large/005Kyrj9ly1gbmsdpl4rfj30su0pfju2.jpg)

# 2. Demo
## 2.1 堆栈
```
Thread 9 (LWP 1386):
#0  0x0000007faec8fd28 in ?? ()
#1  0x0000007faf208190 in osal_memcpy (dst=0x7f0e6cc727, src=0x7f08024180, count=32477) at vdi/linux/vdi_osal.c:335
#2  0x0000007faf205278 in vdi_write_memory (core_idx=3, dst_addr=17924376359, src_data=0x7f08024180 "", len=32477, endian=16) at vdi/linux/vdi.c:1300
... ...
#11 0x000000000044e9b8 in bmMonkey::VPUTask::VideoCapture::read (this=0x7f917f90e8, frame=0x7f08013e40) at /jenkins/projects/AI_BSP_bmMonkey_daily_build/bmMonkey/src/bmMonkey.cpp:279
#12 0x000000000044ef3c in bmMonkey::VPUTask::run (this=0x4b8900, seq=2) at /jenkins/projects/AI_BSP_bmMonkey_daily_build/bmMonkey/src/bmMonkey.cpp:326
... ...
#19 0x0000007faeee73bc in ?? ()
Backtrace stopped: previous frame identical to this frame (corrupt stack?)
```

这里就以#12和#11栈帧为例


## 2.2 查看#12栈帧(caller)
```
(gdb) f 12
#12 0x000000000044ef3c in bmMonkey::VPUTask::run (this=0x4b8900, seq=2) at 

(gdb) i r
x0             0x7f0e6cc727	545702856487
x1             0x7f08024a79	545595214457
x2             0x7594	30100
x3             0x7f0e6ccfe0	545702858720
x4             0x7f0802c05d	545595244637
x5             0x7f0e6d4604	545702888964
x6             0xced9c821daa46d83	-3541579584222499453
x7             0xae3ab9e9ba49762c	-5892192748956977620
x8             0x882dfd5053b622c8	-8633966389155716408
x9             0x10f14ede4ad483f6	1220843690639262710
x10            0x544ccab1c46ccb2	379653303891840178
x11            0xe324afdbaeaae7b	1022962518989647483
x12            0xb051c1241528b35f	-5741595689202699425
x13            0xd87b19b469eae132	-2847654076719898318
x14            0x7	7
x15            0x2dc62c8656e5	50329173776101
x16            0x7faf233440	548399166528
x17            0x7faec8fc10	548393253904
x18            0x0	0
x19            0x7f08007df8	545595096568
x20            0x4b8900	4950272
x21            0x7fc88517de	548825012190
x22            0x7fc88517df	548825012191
x23            0x0	0
x24            0x4bc170	4964720
x25            0x1000	4096
x26            0x1	1
x27            0x7fb201f030	548447318064
x28            0x7fc88517e8	548825012200
x29            0x7f917f90b0	547901903024
x30            0x44ef3c	4517692
sp             0x7f917f90b0	0x7f917f90b0
pc             0x44ef3c	0x44ef3c <bmMonkey::VPUTask::run(unsigned long)+720>
cpsr           0x20000000	[ EL=0 C ]
fpsr           0x10	16
fpcr           0x0	0
```

反汇编当前函数
```
(gdb) disas
Dump of assembler code for function bmMonkey::VPUTask::run(unsigned long):
   0x000000000044ec6c <+0>:	stp	x29, x30, [sp,#-352]!
   0x000000000044ec70 <+4>:	mov	x29, sp
   0x000000000044ec74 <+8>:	stp	x19, x20, [sp,#16]
   0x000000000044ec78 <+12>:	str	x0, [x29,#40]
   0x000000000044ec7c <+16>:	str	x1, [x29,#32]
   0x000000000044ec80 <+20>:	ldr	x0, [x29,#40]
   0x000000000044ec84 <+24>:	bl	0x449484 <bmMonkey::Task::getName[abi:cxx11]() const>

   ... ...
   
   0x000000000044ef1c <+688>:	and	w0, w0, #0xff
   0x000000000044ef20 <+692>:	eor	w0, w0, #0x1
   0x000000000044ef24 <+696>:	and	w0, w0, #0xff
   0x000000000044ef28 <+700>:	cmp	w0, #0x0
   0x000000000044ef2c <+704>:	b.eq	0x44f070 <bmMonkey::VPUTask::run(unsigned long)+1028>
   0x000000000044ef30 <+708>:	ldr	x1, [x29,#48]
   0x000000000044ef34 <+712>:	add	x0, x29, #0x38
   0x000000000044ef38 <+716>:	bl	0x44e850 <bmMonkey::VPUTask::VideoCapture::read(AVFrame*)>
=> 0x000000000044ef3c <+720>:	and	w0, w0, #0xff
   0x000000000044ef40 <+724>:	strb	w0, [x29,#335]
   0x000000000044ef44 <+728>:	ldrb	w0, [x29,#335]
   0x000000000044ef48 <+732>:	eor	w0, w0, #0x1
   0x000000000044ef4c <+736>:	and	w0, w0, #0xff
   0x000000000044ef50 <+740>:	cmp	w0, #0x0
   
   ... ...
   
   0x000000000044f114 <+1192>:	ldp	x19, x20, [sp,#16]
   0x000000000044f118 <+1196>:	ldp	x29, x30, [sp],#352
   0x000000000044f11c <+1200>:	ret
End of assembler dump.
```

先看栈帧保存操作
```
   0x000000000044ec6c <+0>:	stp	x29, x30, [sp,#-352]!
   0x000000000044ec70 <+4>:	mov	x29, sp
   0x000000000044ec74 <+8>:	stp	x19, x20, [sp,#16]
```

目前获取的信息如下
- #12保存的寄存器有: fp, lr, x19, x20
- 当前fp=0x7f917f90b0
- 下一条待执行的指令地址为0x44ef3c


最后函数退出前，会再恢复
```
   0x000000000044f114 <+1192>:	ldp	x19, x20, [sp,#16]
   0x000000000044f118 <+1196>:	ldp	x29, x30, [sp],#352
   0x000000000044f11c <+1200>:	ret
```

## 2.3 查看#11栈帧(callee)
```
(gdb) f 11
#11 0x000000000044e9b8 in bmMonkey::VPUTask::VideoCapture::read (this=0x7f917f90e8, frame=0x7f08013e40) at 

(gdb) i r
x0             0x7f0e6cc727	545702856487
x1             0x7f08024a79	545595214457
x2             0x7594	30100
x3             0x7f0e6ccfe0	545702858720
x4             0x7f0802c05d	545595244637
x5             0x7f0e6d4604	545702888964
x6             0xced9c821daa46d83	-3541579584222499453
x7             0xae3ab9e9ba49762c	-5892192748956977620
x8             0x882dfd5053b622c8	-8633966389155716408
x9             0x10f14ede4ad483f6	1220843690639262710
x10            0x544ccab1c46ccb2	379653303891840178
x11            0xe324afdbaeaae7b	1022962518989647483
x12            0xb051c1241528b35f	-5741595689202699425
x13            0xd87b19b469eae132	-2847654076719898318
x14            0x7	7
x15            0x2dc62c8656e5	50329173776101
x16            0x7faf233440	548399166528
x17            0x7faec8fc10	548393253904
x18            0x0	0
x19            0x7f08007df8	545595096568
x20            0x4b8900	4950272
x21            0x7fc88517de	548825012190
x22            0x7fc88517df	548825012191
x23            0x0	0
x24            0x4bc170	4964720
x25            0x1000	4096
x26            0x1	1
x27            0x7fb201f030	548447318064
x28            0x7fc88517e8	548825012200
x29            0x7f917f9040	547901902912
x30            0x44e9b8	4516280
sp             0x7f917f9040	0x7f917f9040
pc             0x44e9b8	0x44e9b8 <bmMonkey::VPUTask::VideoCapture::read(AVFrame*)+360>
cpsr           0x20000000	[ EL=0 C ]
fpsr           0x10	16
fpcr           0x0	0
```

反汇编当前函数
```
(gdb) disas
Dump of assembler code for function bmMonkey::VPUTask::VideoCapture::read(AVFrame*):
   0x000000000044e850 <+0>:	stp	x29, x30, [sp,#-112]!
   0x000000000044e854 <+4>:	mov	x29, sp
   0x000000000044e858 <+8>:	str	x19, [sp,#16]
   0x000000000044e85c <+12>:	str	x0, [x29,#40]
   0x000000000044e860 <+16>:	str	x1, [x29,#32]
   0x000000000044e864 <+20>:	ldr	x0, [x29,#40]
   0x000000000044e868 <+24>:	ldr	x2, [x0,#96]
   0x000000000044e86c <+28>:	ldr	x0, [x29,#40]
   0x000000000044e870 <+32>:	add	x0, x0, #0x8
   0x000000000044e874 <+36>:	mov	x1, x0
   0x000000000044e878 <+40>:	mov	x0, x2
   0x000000000044e87c <+44>:	bl	0x447350 <av_read_frame@plt>

   ... ...
   0x000000000044e9ac <+348>:	mov	x1, x0
   0x000000000044e9b0 <+352>:	mov	x0, x2
   0x000000000044e9b4 <+356>:	bl	0x446cc0 <avcodec_send_packet@plt>
=> 0x000000000044e9b8 <+360>:	str	w0, [x29,#108]
   0x000000000044e9bc <+364>:	ldr	w0, [x29,#108]
   0x000000000044e9c0 <+368>:	cmp	w0, #0x0

   ... ...
   
   0x000000000044ec60 <+1040>:	ldr	x19, [sp,#16]
   0x000000000044ec64 <+1044>:	ldp	x29, x30, [sp],#112
   0x000000000044ec68 <+1048>:	ret
End of assembler dump.
```


先看栈帧保存操作
```
   0x000000000044e850 <+0>:	stp	x29, x30, [sp,#-112]!
   0x000000000044e854 <+4>:	mov	x29, sp
   0x000000000044e858 <+8>:	str	x19, [sp,#16]
```
这里保存了fp/lr/x19三个寄存器值

最后函数退出前，会再恢复
```
   0x000000000044ec60 <+1040>:	ldr	x19, [sp,#16]
   0x000000000044ec64 <+1044>:	ldp	x29, x30, [sp],#112
   0x000000000044ec68 <+1048>:	ret
```

#11栈帧里， 存储了caller也就是#12栈帧的部分信息
```
(gdb) x/14xg 0x7f917f9040 
0x7f917f9040:	0x0000007f917f90b0	0x000000000044ef3c
0x7f917f9050:	0x0000007f08007df8	0x0000007f917f9090
0x7f917f9060:	0x0000007f08013e40	0x0000007f917f90e8
0x7f917f9070:	0x0000007f917f9090	0x000000050000ffff
0x7f917f9080:	0x0000007f917f90b0	0x000000000044ef1c
0x7f917f9090:	0x0000000000989680	0x00000000004b8928
0x7f917f90a0:	0x0000000500000005	0x00000000004b8928
```

前面三个64bit值分别保存的是
- 0x0000007f917f90b0是#12栈帧的fp
- 0x000000000044ef3c是#12栈帧里待执行的下一条指令地址
- 0x0000007f08007df8是#12栈帧里的x19

也就是，我们可以通过#11推导出#12. 以此类推，#12也可以推导出#13等。

# 3. 总结
- 默认情况下，arm64平台的每个栈帧都会保存fp(x29)和lr(x30)两个寄存器. 通过递归这两个寄存器，可以得到整个backtrace.
- -fomit-frame-pointer编译选项可以优化掉fp

---


![程序员自我修养](http://ww1.sinaimg.cn/large/005Kyrj9ly1gbvsonijdoj3076076wex.jpg)

<center>
程序员自我修养(ID: dumphex)
</center>

---
