---
title: C++的全局对象
date: 2020-03-15 14:47:21
tags:
- global object
- _start
- __libc_start_main 
- __libc_csu_init
- __static_initialization_and_destruction_0
- __run_exit_handlers
categories: C/C++
---

本文分析了全局对象的构造和析构过程。

<!-- more -->

## 1. 测试环境
- Linux ubuntu18arm64 4.15.0-76-generic #86-Ubuntu SMP Fri Jan 17 17:25:58 UTC 2020 aarch64 aarch64 aarch64 GNU/Linux
- gcc version 7.4.0 (Ubuntu/Linaro 7.4.0-1ubuntu1~18.04.1)
- glibc 2.27
- c++11


## 2. 调试分析

### 2.1 测试源码 
```cpp
class Base {
 public:
  Base(int i) : m_var(i) {
  }

  ~Base() {
    m_var = 0;
  }

 private:
  int m_var;
};

Base global_obj(4);
```

### 2.2 构造

全局对象的构造函数调用堆栈如下:

```asm
(gdb) bt
#0  Base::Base (this=0xaaaaaaabc018 <global_obj>, i=4) at /home/timzhang/project/github/dumphex/cppTestSuite/src/objects.cc:5
#1  0x0000aaaaaaaab054 in __static_initialization_and_destruction_0 (__initialize_p=1, __priority=65535) at /home/timzhang/project/github/dumphex/cppTestSuite/src/objects.cc:30
#2  0x0000aaaaaaaab090 in _GLOBAL__sub_I__Z5stackv () at /home/timzhang/project/github/dumphex/cppTestSuite/src/objects.cc:39
#3  0x0000aaaaaaaab138 in __libc_csu_init ()
#4  0x0000fffff7d05688 in __libc_start_main (main=0xfffff7fc2190, argc=0, argv=0xfffffffff3e8, init=0x2, fini=<optimized out>, rtld_fini=<optimized out>, stack_end=<optimized out>)
    at ../csu/libc-start.c:266
#5  0x0000aaaaaaaaadb4 in _start ()
Backtrace stopped: previous frame identical to this frame (corrupt stack?)
```

下面从#5往上推算全局对象的构造过程。

#### 2.2.1 _start

查看Linux程序的入口点
```shell
$ readelf -h objects 
ELF Header:
  Magic:   7f 45 4c 46 02 01 01 00 00 00 00 00 00 00 00 00 
  Class:                             ELF64
  Data:                              2's complement, little endian
  Version:                           1 (current)
  OS/ABI:                            UNIX - System V
  ABI Version:                       0
  Type:                              DYN (Shared object file)
  Machine:                           AArch64
  Version:                           0x1
  Entry point address:               0xd80
  Start of program headers:          64 (bytes into file)
  Start of section headers:          33240 (bytes into file)
  Flags:                             0x0
  Size of this header:               64 (bytes)
  Size of program headers:           56 (bytes)
  Number of program headers:         9
  Size of section headers:           64 (bytes)
  Number of section headers:         34
  Section header string table index: 33
```

通过Entry point address:               0xd80， 可以找到程序的入口点位于程序偏移0xd80处

objects程序的内存映射如下
```
aaaaaaaaa000-aaaaaaaac000 r-xp 00000000 fd:00 2883810                    /home/timzhang/project/github/dumphex/cppTestSuite/out/bin/objects
aaaaaaabb000-aaaaaaabc000 r--p 00001000 fd:00 2883810                    /home/timzhang/project/github/dumphex/cppTestSuite/out/bin/objects
aaaaaaabc000-aaaaaaabd000 rw-p 00002000 fd:00 2883810                    /home/timzhang/project/github/dumphex/cppTestSuite/out/bin/objects
```

反汇编入口点地址如下
```asm
(gdb) disas 0xaaaaaaaaa000+0xd80
Dump of assembler code for function _start:
   0x0000aaaaaaaaad80 <+0>:	mov	x29, #0x0                   	// #0
   0x0000aaaaaaaaad84 <+4>:	mov	x30, #0x0                   	// #0
   0x0000aaaaaaaaad88 <+8>:	mov	x5, x0
   0x0000aaaaaaaaad8c <+12>:	ldr	x1, [sp]
   0x0000aaaaaaaaad90 <+16>:	add	x2, sp, #0x8
   0x0000aaaaaaaaad94 <+20>:	mov	x6, sp
   0x0000aaaaaaaaad98 <+24>:	adrp	x0, 0xaaaaaaabb000
   0x0000aaaaaaaaad9c <+28>:	ldr	x0, [x0, #4032]
   0x0000aaaaaaaaada0 <+32>:	adrp	x3, 0xaaaaaaabb000
   0x0000aaaaaaaaada4 <+36>:	ldr	x3, [x3, #4048]
   0x0000aaaaaaaaada8 <+40>:	adrp	x4, 0xaaaaaaabb000
   0x0000aaaaaaaaadac <+44>:	ldr	x4, [x4, #4064]
   0x0000aaaaaaaaadb0 <+48>:	bl	0xaaaaaaaaad00 <__libc_start_main@plt>
   0x0000aaaaaaaaadb4 <+52>:	bl	0xaaaaaaaaad50 <abort@plt>
End of assembler dump.
```

可以看到，Linux下用户态程序的入口点是_start()函数

> 源文件: glibc/ports/sysdeps/aarch64/start.S

```asm
        .text
        .globl _start
        .type _start,#function
_start:
        /* Create an initial frame with 0 LR and FP */
        mov     x29, #0
        mov     x30, #0
        mov     x29, sp

        /* Setup rtld_fini in argument register */
        mov     x5, x0

        /* Load argc and a pointer to argv */
        ldr     x1, [sp, #0] 
        add     x2, sp, #8

        /* Setup stack limit in argument register */
        mov     x6, sp

#ifdef SHARED
        adrp    x0, :got:main
        ldr     x0, [x0, #:got_lo12:main]

        adrp    x3, :got:__libc_csu_init
        ldr     x3, [x3, #:got_lo12:__libc_csu_init]

        adrp    x4, :got:__libc_csu_fini
        ldr     x4, [x4, #:got_lo12:__libc_csu_fini]
#else
        /* Set up the other arguments in registers */
        ldr     x0, =main
        ldr     x3, =__libc_csu_init
        ldr     x4, =__libc_csu_fini
#endif

        /* __libc_start_main (main, argc, argv, init, fini, rtld_fini,
                              stack_end) */

        /* Let the libc call main and exit with its return code.  */
        bl      __libc_start_main

        /* should never get here....*/
        bl      abort
```

这里需要重点关注的是第4个参数: x3 = __libc_csu_init

#### 2.2.2 __libc_start_main

> 源文件: glibc/csu/libc-start.c

__libc_start_main()代码较多， 这里简单列出相关实现:
```c
  if (init)
    (*init) (argc, argv, __environ MAIN_AUXVEC_PARAM);
    
  result = main (argc, argv, __environ MAIN_AUXVEC_PARAM);
  
  exit(result);
```

相关实现主要有三点
- 调用*init(), init就是在_start中传入的x3 = __libc_csu_init

- 调用main(), 执行程序

- exit(): 负责调用退出处理函数，如回调函数或析构函数

#### 2.2.3 __libc_csu_init

> 源文件: glibc/csu/elf-init.c

```c
/* These functions are passed to __libc_start_main by the startup code.
   These get statically linked into each program.  For dynamically linked
   programs, this module will come from libc_nonshared.a and differs from
   the libc.a module in that it doesn't call the preinit array.  */


void
__libc_csu_init (int argc, char **argv, char **envp)
{
  /* For dynamically linked executables the preinit array is executed by
     the dynamic linker (before initializing any shared object).  */

#ifndef LIBC_NONSHARED
  /* For static executables, preinit happens right before init.  */
  {
    const size_t size = __preinit_array_end - __preinit_array_start;
    size_t i;
    for (i = 0; i < size; i++)
      (*__preinit_array_start [i]) (argc, argv, envp);
  }
#endif

  _init (); 

  const size_t size = __init_array_end - __init_array_start;
  for (size_t i = 0; i < size; i++)
      (*__init_array_start [i]) (argc, argv, envp);
}
```

_init()函数位于程序的.init section, 
```asm
(gdb) disas 0xaaaaaaaaa000+0xc98
Dump of assembler code for function _init:
   0x0000aaaaaaaaac98 <+0>:	stp	x29, x30, [sp, #-16]!
   0x0000aaaaaaaaac9c <+4>:	mov	x29, sp
   0x0000aaaaaaaaaca0 <+8>:	bl	0xaaaaaaaaadb8 <call_weak_fn>
   0x0000aaaaaaaaaca4 <+12>:	ldp	x29, x30, [sp], #16
   0x0000aaaaaaaaaca8 <+16>:	ret
End of assembler dump.

(gdb) disas 0xaaaaaaaaadb8
Dump of assembler code for function call_weak_fn:
   0x0000aaaaaaaaadb8 <+0>:	adrp	x0, 0xaaaaaaabb000
   0x0000aaaaaaaaadbc <+4>:	ldr	x0, [x0, #4072]
   0x0000aaaaaaaaadc0 <+8>:	cbz	x0, 0xaaaaaaaaadc8 <call_weak_fn+16>
   0x0000aaaaaaaaadc4 <+12>:	b	0xaaaaaaaaad70 <__gmon_start__@plt>
   0x0000aaaaaaaaadc8 <+16>:	ret
End of assembler dump.

(gdb) x/4xw 0xaaaaaaabb000+4072
0xaaaaaaabbfe8:	0x00000000	0x00000000	0x00000000	0x00000000
```
这里看起来，_init()函数什么也没做。


继续看最后的循环部分

由于没有找到__init_array_start/__init_array_end的相关定义， 这里反汇编__libc_csu_init()来分析

```asm
(gdb) disas __libc_csu_init
Dump of assembler code for function __libc_csu_init:
   0x0000aaaaaaaab0d8 <+0>:	stp	x29, x30, [sp, #-64]!
   0x0000aaaaaaaab0dc <+4>:	mov	x29, sp
   0x0000aaaaaaaab0e0 <+8>:	stp	x20, x21, [sp, #24]
   0x0000aaaaaaaab0e4 <+12>:	adrp	x20, 0xaaaaaaabb000
   0x0000aaaaaaaab0e8 <+16>:	adrp	x21, 0xaaaaaaabb000
   0x0000aaaaaaaab0ec <+20>:	add	x20, x20, #0xd28
   0x0000aaaaaaaab0f0 <+24>:	add	x21, x21, #0xd18
   0x0000aaaaaaaab0f4 <+28>:	stp	x22, x23, [sp, #40]
   0x0000aaaaaaaab0f8 <+32>:	sub	x20, x20, x21
   0x0000aaaaaaaab0fc <+36>:	str	x24, [sp, #56]
   0x0000aaaaaaaab100 <+40>:	mov	w22, w0
   0x0000aaaaaaaab104 <+44>:	mov	x23, x1
   0x0000aaaaaaaab108 <+48>:	asr	x20, x20, #3
   0x0000aaaaaaaab10c <+52>:	mov	x24, x2
   0x0000aaaaaaaab110 <+56>:	bl	0xaaaaaaaaac98 <_init>
   0x0000aaaaaaaab114 <+60>:	cbz	x20, 0xaaaaaaaab144 <__libc_csu_init+108>
   0x0000aaaaaaaab118 <+64>:	str	x19, [x29, #16]
   0x0000aaaaaaaab11c <+68>:	mov	x19, #0x0                   	// #0
   0x0000aaaaaaaab120 <+72>:	ldr	x3, [x21, x19, lsl #3]
   0x0000aaaaaaaab124 <+76>:	mov	x2, x24
   0x0000aaaaaaaab128 <+80>:	mov	x1, x23
   0x0000aaaaaaaab12c <+84>:	mov	w0, w22
   0x0000aaaaaaaab130 <+88>:	add	x19, x19, #0x1
   0x0000aaaaaaaab134 <+92>:	blr	x3
=> 0x0000aaaaaaaab138 <+96>:	cmp	x20, x19
   0x0000aaaaaaaab13c <+100>:	b.ne	0xaaaaaaaab120 <__libc_csu_init+72>  // b.any
   0x0000aaaaaaaab140 <+104>:	ldr	x19, [x29, #16]
   0x0000aaaaaaaab144 <+108>:	ldp	x20, x21, [sp, #24]
   0x0000aaaaaaaab148 <+112>:	ldp	x22, x23, [sp, #40]
   0x0000aaaaaaaab14c <+116>:	ldr	x24, [sp, #56]
   0x0000aaaaaaaab150 <+120>:	ldp	x29, x30, [sp], #64
   0x0000aaaaaaaab154 <+124>:	ret
End of assembler dump.
```

__init_array_start = x21 = 0xaaaaaaabb000 + 0xd18 = 0xaaaaaaabbd18

__init_array_end = x20 = 0xaaaaaaabb000 + 0xd28 = 0xaaaaaaabbd28

__init_array_start[]数组主要存储了两个函数
```
(gdb) x/2xg 0xaaaaaaabbd18
0xaaaaaaabbd18:	0x0000aaaaaaaaae80	0x0000aaaaaaaab07c

(gdb) disas 0x0000aaaaaaaaae80
Dump of assembler code for function frame_dummy:
   0x0000aaaaaaaaae80 <+0>:	b	0xaaaaaaaaae00 <register_tm_clones>
End of assembler dump.

(gdb) disas 0x0000aaaaaaaab07c
Dump of assembler code for function _GLOBAL__sub_I__Z5stackv():
   0x0000aaaaaaaab07c <+0>:	stp	x29, x30, [sp, #-16]!
   0x0000aaaaaaaab080 <+4>:	mov	x29, sp
   0x0000aaaaaaaab084 <+8>:	mov	w1, #0xffff                	// #65535
   0x0000aaaaaaaab088 <+12>:	mov	w0, #0x1                   	// #1
   0x0000aaaaaaaab08c <+16>:	bl	0xaaaaaaaaaff0 <__static_initialization_and_destruction_0(int, int)>
   0x0000aaaaaaaab090 <+20>:	ldp	x29, x30, [sp], #16
   0x0000aaaaaaaab094 <+24>:	ret
End of assembler dump.
```

每个CPP源文件，都是个编译单元。在该编译单元中，编译器会生成特定的函数初始化当前编译单元的全局对象，而这些函数都统一放在__init_array_start[]数组。

#### 2.2.4 _GLOBAL__sub_I__Z5stackv
此类函数名称类似如下
- _GLOBAL__sub_I__Z5stackv
- _GLOBAL__sub_I_b1
- _GLOBAL__sub_I_b2
- ... ...

这类函数，会调用另一个函数__static_initialization_and_destruction_0
```asm
(gdb) disas
Dump of assembler code for function _GLOBAL__sub_I__Z5stackv():
   0x0000aaaaaaaab07c <+0>:	stp	x29, x30, [sp, #-16]!
   0x0000aaaaaaaab080 <+4>:	mov	x29, sp
   0x0000aaaaaaaab084 <+8>:	mov	w1, #0xffff                	// #65535
   0x0000aaaaaaaab088 <+12>:	mov	w0, #0x1                   	// #1
   0x0000aaaaaaaab08c <+16>:	bl	0xaaaaaaaaaff0 <__static_initialization_and_destruction_0(int, int)>
=> 0x0000aaaaaaaab090 <+20>:	ldp	x29, x30, [sp], #16
   0x0000aaaaaaaab094 <+24>:	ret
End of assembler dump.
```

#### 2.2.5 __static_initialization_and_destruction_0

该函数主要用于完成当前编译单元内的全局对象的构造和注册析构函数。

__static_initialization_and_destruction_0的汇编code如下
```asm
(gdb) disas
Dump of assembler code for function __static_initialization_and_destruction_0(int, int):
   0x0000aaaaaaaaaff0 <+0>:	stp	x29, x30, [sp, #-32]!
   0x0000aaaaaaaaaff4 <+4>:	mov	x29, sp
   0x0000aaaaaaaaaff8 <+8>:	str	w0, [x29, #28]
   0x0000aaaaaaaaaffc <+12>:	str	w1, [x29, #24]
   0x0000aaaaaaaab000 <+16>:	ldr	w0, [x29, #28]
   0x0000aaaaaaaab004 <+20>:	cmp	w0, #0x1
   0x0000aaaaaaaab008 <+24>:	b.ne	0xaaaaaaaab070 <__static_initialization_and_destruction_0(int, int)+128>  // b.any
   0x0000aaaaaaaab00c <+28>:	ldr	w1, [x29, #24]
   0x0000aaaaaaaab010 <+32>:	mov	w0, #0xffff                	// #65535
   0x0000aaaaaaaab014 <+36>:	cmp	w1, w0
   0x0000aaaaaaaab018 <+40>:	b.ne	0xaaaaaaaab070 <__static_initialization_and_destruction_0(int, int)+128>  // b.any
   0x0000aaaaaaaab01c <+44>:	adrp	x0, 0xaaaaaaabc000
   0x0000aaaaaaaab020 <+48>:	add	x0, x0, #0x20
   0x0000aaaaaaaab024 <+52>:	bl	0xaaaaaaaaad40 <_ZNSt8ios_base4InitC1Ev@plt>
   0x0000aaaaaaaab028 <+56>:	adrp	x0, 0xaaaaaaabc000
   0x0000aaaaaaaab02c <+60>:	add	x2, x0, #0x8
   0x0000aaaaaaaab030 <+64>:	adrp	x0, 0xaaaaaaabc000
   0x0000aaaaaaaab034 <+68>:	add	x1, x0, #0x20
   0x0000aaaaaaaab038 <+72>:	adrp	x0, 0xaaaaaaabb000
   0x0000aaaaaaaab03c <+76>:	ldr	x0, [x0, #4088]
   0x0000aaaaaaaab040 <+80>:	bl	0xaaaaaaaaad30 <__cxa_atexit@plt>
   0x0000aaaaaaaab044 <+84>:	adrp	x0, 0xaaaaaaabc000
   0x0000aaaaaaaab048 <+88>:	add	x0, x0, #0x18
   0x0000aaaaaaaab04c <+92>:	mov	w1, #0x4                   	// #4
   0x0000aaaaaaaab050 <+96>:	bl	0xaaaaaaaab098 <Base::Base(int)>
=> 0x0000aaaaaaaab054 <+100>:	adrp	x0, 0xaaaaaaabc000
   0x0000aaaaaaaab058 <+104>:	add	x2, x0, #0x8
   0x0000aaaaaaaab05c <+108>:	adrp	x0, 0xaaaaaaabc000
   0x0000aaaaaaaab060 <+112>:	add	x1, x0, #0x18
   0x0000aaaaaaaab064 <+116>:	adrp	x0, 0xaaaaaaaab000 <__static_initialization_and_destruction_0(int, int)+16>
   0x0000aaaaaaaab068 <+120>:	add	x0, x0, #0xbc
   0x0000aaaaaaaab06c <+124>:	bl	0xaaaaaaaaad30 <__cxa_atexit@plt>
   0x0000aaaaaaaab070 <+128>:	nop
   0x0000aaaaaaaab074 <+132>:	ldp	x29, x30, [sp], #32
   0x0000aaaaaaaab078 <+136>:	ret
End of assembler dump.
```

**全局对象的构造函数调用**
```asm
   0x0000aaaaaaaab044 <+84>:	adrp	x0, 0xaaaaaaabc000
   0x0000aaaaaaaab048 <+88>:	add	x0, x0, #0x18
   0x0000aaaaaaaab04c <+92>:	mov	w1, #0x4                   	// #4
   0x0000aaaaaaaab050 <+96>:	bl	0xaaaaaaaab098 <Base::Base(int)>
```

传给构造函数的参数如下
- 第1个参数是全局对象的地址x0 = 0xaaaaaaabc018
- 第2个参数是w1 = 4


**全局对象的析构函数注册**
```asm
=> 0x0000aaaaaaaab054 <+100>:	adrp	x0, 0xaaaaaaabc000
   0x0000aaaaaaaab058 <+104>:	add	x2, x0, #0x8
   0x0000aaaaaaaab05c <+108>:	adrp	x0, 0xaaaaaaabc000
   0x0000aaaaaaaab060 <+112>:	add	x1, x0, #0x18
   0x0000aaaaaaaab064 <+116>:	adrp	x0, 0xaaaaaaaab000 <__static_initialization_and_destruction_0(int, int)+16>
   0x0000aaaaaaaab068 <+120>:	add	x0, x0, #0xbc
   0x0000aaaaaaaab06c <+124>:	bl	0xaaaaaaaaad30 <__cxa_atexit@plt>
```

和之前分析的局部静态对象类似，这里调用__cxa_atexit()注册全局对象的析构函数
- 第1个参数x0 = 0x0000aaaaaaaab0bc是Base::~Base()
- 第2个参数x1 = 0xaaaaaaabc018是全局对象的地址
- 第3个参数x2 = 0xaaaaaaabc008是dso handler


### 2.3 析构

全局对象的析构函数调用堆栈如下:

```asm
(gdb) bt
#0  Base::~Base (this=0xaaaaaaabc018 <global_obj>, __in_chrg=<optimized out>) at /home/timzhang/project/github/dumphex/cppTestSuite/src/objects.cc:9
#1  0x0000fffff7d19e34 in __run_exit_handlers (status=0, listp=0xfffff7e385a0 <__exit_funcs>, run_list_atexit=255, run_list_atexit@entry=true, run_dtors=run_dtors@entry=true) at exit.c:108
#2  0x0000fffff7d19f6c in __GI_exit (status=<optimized out>) at exit.c:139
#3  0x0000fffff7d056e4 in __libc_start_main (main=0x0, argc=0, argv=0x0, init=<optimized out>, fini=<optimized out>, rtld_fini=<optimized out>, stack_end=<optimized out>) at ../csu/libc-start.c:344
#4  0x0000aaaaaaaaadb4 in _start ()
Backtrace stopped: previous frame identical to this frame (corrupt stack?)
```
全局对象的析构和之前分析的局部静态对象的析构类似， 都是在程序退出调用exit()时触发析构函数的调用。

## 3. 总结
- 全局对象的构造发生在main()之前的__libc_csu_init(), 该函数将调用每个编译单元生成的特殊函数，这些特殊函数调用全局对象的构造函数并注册其析构函数
- 全局对象的析构发生在main()之后的exit(), 调用前面注册的析构函数

---

![程序员自我修养](http://ww1.sinaimg.cn/large/005Kyrj9ly1gbvsonijdoj3076076wex.jpg)

<center>
程序员自我修养(ID: dumphex)
</center>

---
