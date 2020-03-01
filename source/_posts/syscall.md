---
title: 系统调用实现原理
date: 2020-03-01 14:59:55
modified: 2020-03-01 16:25:26
tags:
- syscall
- arm64
- kernel
categories: Linux
---

本文以mmap系统调用为例，描述它在用户态和内核态的执行过程。

<!-- more -->

# 1. 系统环境
- Linux + arm64
- kernel 4.9
- glibc 2.17


# 2. 系统调用执行过程

## 2.1 用户态

### 2.1.1 mmap的实现
> 源文件: glibc/ports/sysdeps/unix/sysv/linux/aarch64/mmap.c

```c
__ptr_t
__mmap (__ptr_t addr, size_t len, int prot, int flags, int fd, off_t offset)
{
  return (__ptr_t) INLINE_SYSCALL (mmap, 6, addr, len, prot, flags, fd, offset);
}

weak_alias (__mmap, mmap)
weak_alias (__mmap, mmap64)
weak_alias (__mmap, __mmap64)
```

**INLINE_SYSCALL**的实现如下

> 源文件: glibc/ports/sysdeps/unix/sysv/linux/aarch64/sysdep.h

```c
/* Define a macro which expands into the inline wrapper code for a system
   call.  */
# undef INLINE_SYSCALL
# define INLINE_SYSCALL(name, nr, args...)                                \
  ({ unsigned long _sys_result = INTERNAL_SYSCALL (name, , nr, args);        \
     if (__builtin_expect (INTERNAL_SYSCALL_ERROR_P (_sys_result, ), 0))\
       {                                                                \
         __set_errno (INTERNAL_SYSCALL_ERRNO (_sys_result, ));                \
         _sys_result = (unsigned long) -1;                                \
       }                                                                \
     (long) _sys_result; })
```

流程如下:
- 调用INTERNAL_SYSCALL执行系统调用
- 判断返回值_sys_result

  若为0，则直接返回
  
  若不为0，则将返回值_sys_result**取负**设置到**errno**, 返回-1

**INTERNAL_SYSCALL**的实现如下
```c
# undef INTERNAL_SYSCALL
# define INTERNAL_SYSCALL(name, err, nr, args...)               \
        INTERNAL_SYSCALL_RAW(SYS_ify(name), err, nr, args)
```

**SYS_ify**是个宏，用于将syscall name转换为syscall number
```c
/* For Linux we can use the system call table in the header file
        /usr/include/asm/unistd.h
   of the kernel.  But these symbols do not follow the SYS_* syntax
   so we have to redefine the `SYS_ify' macro here.  */
#undef SYS_ify
#define SYS_ify(syscall_name)        (__NR_##syscall_name)
```
这里将mmap转换成了__NR_mmap

再看**INTERNAL_SYSCALL_RAW**的实现
```c
# undef INTERNAL_SYSCALL_RAW
# define INTERNAL_SYSCALL_RAW(name, err, nr, args...)           \
  ({ long _sys_result;                                          \
     {                                                          \
       LOAD_ARGS_##nr (args)                                    \
       register long _x8 asm ("x8") = (name);                   \
       asm volatile ("svc       0       // syscall " # name     \
                     : "=r" (_x0) : "r"(_x8) ASM_ARGS_##nr : "memory"); \
       _sys_result = _x0;                                       \
     }                                                          \
     _sys_result; })
```
nr为mmap的参数个数，这里为6。

LOAD_ARGS_##nr对应LOAD_ARGS_6, 这个宏用于将所有的32bit参数转换为64bit， 并将相应的参数保存到_x0/_x1/_x2/_x3/_x4/_x5中

```c
# define LOAD_ARGS_0()                          \
  register long _x0 asm ("x0");

# define ASM_ARGS_0
# define LOAD_ARGS_1(x0)                        \
  long _x0tmp = (long) (x0);                    \
  LOAD_ARGS_0 ()                                \
  _x0 = _x0tmp;
# define ASM_ARGS_1     "r" (_x0)
# define LOAD_ARGS_2(x0, x1)                    \
  long _x1tmp = (long) (x1);                    \
  LOAD_ARGS_1 (x0)                              \
  register long _x1 asm ("x1") = _x1tmp;
# define ASM_ARGS_2     ASM_ARGS_1, "r" (_x1)
# define LOAD_ARGS_3(x0, x1, x2)                \
  long _x2tmp = (long) (x2);                    \
  LOAD_ARGS_2 (x0, x1)                          \
  register long _x2 asm ("x2") = _x2tmp;
# define ASM_ARGS_3     ASM_ARGS_2, "r" (_x2)
# define LOAD_ARGS_4(x0, x1, x2, x3)            \
  long _x3tmp = (long) (x3);                    \
  LOAD_ARGS_3 (x0, x1, x2)                      \
  register long _x3 asm ("x3") = _x3tmp;
# define ASM_ARGS_4     ASM_ARGS_3, "r" (_x3)
# define LOAD_ARGS_5(x0, x1, x2, x3, x4)        \
  long _x4tmp = (long) (x4);                    \
  LOAD_ARGS_4 (x0, x1, x2, x3)                  \
  register long _x4 asm ("x4") = _x4tmp;
# define ASM_ARGS_5     ASM_ARGS_4, "r" (_x4)
# define LOAD_ARGS_6(x0, x1, x2, x3, x4, x5)    \
  long _x5tmp = (long) (x5);                    \
  LOAD_ARGS_5 (x0, x1, x2, x3, x4)              \
  register long _x5 asm ("x5") = _x5tmp;
# define ASM_ARGS_6     ASM_ARGS_5, "r" (_x5)
# define LOAD_ARGS_7(x0, x1, x2, x3, x4, x5, x6)\
  long _x6tmp = (long) (x6);                    \
  LOAD_ARGS_6 (x0, x1, x2, x3, x4, x5)          \
  register long _x6 asm ("x6") = _x6tmp;
# define ASM_ARGS_7     ASM_ARGS_6, "r" (_x6)
```

ASM_ARGS_##nr对应ASM_ARGS_6, 用于将x0~x5这6个寄存器作为内联汇编的输入寄存器列表
```c
# define ASM_ARGS_1     "r" (_x0)
# define LOAD_ARGS_2(x0, x1)                    \
  long _x1tmp = (long) (x1);                    \
  LOAD_ARGS_1 (x0)                              \
  register long _x1 asm ("x1") = _x1tmp;
# define ASM_ARGS_2     ASM_ARGS_1, "r" (_x1)
# define LOAD_ARGS_3(x0, x1, x2)                \
  long _x2tmp = (long) (x2);                    \
  LOAD_ARGS_2 (x0, x1)                          \
  register long _x2 asm ("x2") = _x2tmp;
# define ASM_ARGS_3     ASM_ARGS_2, "r" (_x2)
# define LOAD_ARGS_4(x0, x1, x2, x3)            \
  long _x3tmp = (long) (x3);                    \
  LOAD_ARGS_3 (x0, x1, x2)                      \
  register long _x3 asm ("x3") = _x3tmp;
# define ASM_ARGS_4     ASM_ARGS_3, "r" (_x3)
# define LOAD_ARGS_5(x0, x1, x2, x3, x4)        \
  long _x4tmp = (long) (x4);                    \
  LOAD_ARGS_4 (x0, x1, x2, x3)                  \
  register long _x4 asm ("x4") = _x4tmp;
# define ASM_ARGS_5     ASM_ARGS_4, "r" (_x4)
# define LOAD_ARGS_6(x0, x1, x2, x3, x4, x5)    \
  long _x5tmp = (long) (x5);                    \
  LOAD_ARGS_5 (x0, x1, x2, x3, x4)              \
  register long _x5 asm ("x5") = _x5tmp;
# define ASM_ARGS_6     ASM_ARGS_5, "r" (_x5)
```

### 2.1.2 syscall number
每一个系统调用，都有唯一的syscall number

下面看一下__NR_mmap在arm64上是怎么定义的
> 源文件: gcc-linaro-6.3.1-2017.05-x86_64_aarch64-linux-gnu/aarch64-linux-gnu/libc/usr/include/asm-generic/unistd.h

```c
#define __NR_mmap __NR3264_mmap

#define __NR3264_mmap 222
```

也就是，mmap在arm64平台上的syscall number是222


### 2.1.3 反汇编mmap

反汇编libc.so的mmap:
```asm
00000000000c4908 <mmap@@GLIBC_2.17>:
   c4908:       93407c42        sxtw    x2, w2 
   c490c:       93407c63        sxtw    x3, w3 
   c4910:       93407c84        sxtw    x4, w4 
   c4914:       d2801bc8        mov     x8, #0xde                       // #222
   c4918:       d4000001        svc     #0x0   
   c491c:       b140041f        cmn     x0, #0x1, lsl #12
   c4920:       54000048        b.hi    c4928 <mmap@@GLIBC_2.17+0x20>  // b.pmore
   c4924:       d65f03c0        ret    
   c4928:       f00003e1        adrp    x1, 143000 <sys_sigabbrev@@GLIBC_2.17+0x240>
   c492c:       f9472021        ldr     x1, [x1, #3648] 
   c4930:       d53bd042        mrs     x2, tpidr_el0
   c4934:       4b0003e3        neg     w3, w0 
   c4938:       92800000        mov     x0, #0xffffffffffffffff         // #-1
   c493c:       b8216843        str     w3, [x2, x1]
   c4940:       d65f03c0        ret 
```

- 将第3、4、5个参数， 由32bit扩展为64bit

  mmap系统调用的原型如下
  ```c
       #include <sys/mman.h>

       void *mmap(void *addr, size_t length, int prot, int flags,
                  int fd, off_t offset);
  ```
  可看到，prot/flags/fd是32bit的

- syscall number存储到了x8寄存器
- 最后svc 0触发进入内核态
  >Supervisor Call causes an exception to be taken to EL1.
   On executing an SVC instruction, the PE records the exception as a Supervisor Call exception in ESR_ELx, using the
   EC value 0x15 , and the value of the immediate argument.

## 2.2 内核态


### 2.2.1 异常向量表
系统调用切换到内核态后， 首先会进入异常向量表处理。

> 源文件: kernel/arch/arm64/kernel/entry.S
```asm
/*
 * Exception vectors.
 */
        .pushsection ".entry.text", "ax"

        .align  11  
ENTRY(vectors)
        ventry  el1_sync_invalid                // Synchronous EL1t
        ventry  el1_irq_invalid                 // IRQ EL1t
        ventry  el1_fiq_invalid                 // FIQ EL1t
        ventry  el1_error_invalid               // Error EL1t

        ventry  el1_sync                        // Synchronous EL1h
        ventry  el1_irq                         // IRQ EL1h
        ventry  el1_fiq_invalid                 // FIQ EL1h
        ventry  el1_error_invalid               // Error EL1h

        ventry  el0_sync                        // Synchronous 64-bit EL0
        ventry  el0_irq                         // IRQ 64-bit EL0
        ventry  el0_fiq_invalid                 // FIQ 64-bit EL0
        ventry  el0_error_invalid               // Error 64-bit EL0

#ifdef CONFIG_COMPAT
        ventry  el0_sync_compat                 // Synchronous 32-bit EL0
        ventry  el0_irq_compat                  // IRQ 32-bit EL0
        ventry  el0_fiq_invalid_compat          // FIQ 32-bit EL0
        ventry  el0_error_invalid_compat        // Error 32-bit EL0
#else
        ventry  el0_sync_invalid                // Synchronous 32-bit EL0
        ventry  el0_irq_invalid                 // IRQ 32-bit EL0
        ventry  el0_fiq_invalid                 // FIQ 32-bit EL0
        ventry  el0_error_invalid               // Error 32-bit EL0
#endif
END(vectors)
```

用户态的系统调用会在**el0_sync**处理
```asm
/*
 * EL0 mode handlers.
 */
        .align  6
el0_sync:
        kernel_entry 0
        mrs     x25, esr_el1                    // read the syndrome register
        lsr     x24, x25, #ESR_ELx_EC_SHIFT     // exception class
        cmp     x24, #ESR_ELx_EC_SVC64          // SVC in 64-bit state
        b.eq    el0_svc
        cmp     x24, #ESR_ELx_EC_DABT_LOW       // data abort in EL0
        b.eq    el0_da
        cmp     x24, #ESR_ELx_EC_IABT_LOW       // instruction abort in EL0
        b.eq    el0_ia
        cmp     x24, #ESR_ELx_EC_FP_ASIMD       // FP/ASIMD access
        b.eq    el0_fpsimd_acc
        cmp     x24, #ESR_ELx_EC_FP_EXC64       // FP/ASIMD exception
        b.eq    el0_fpsimd_exc
        cmp     x24, #ESR_ELx_EC_SYS64          // configurable trap
        b.eq    el0_sys
        cmp     x24, #ESR_ELx_EC_SP_ALIGN       // stack alignment exception
        b.eq    el0_sp_pc
        cmp     x24, #ESR_ELx_EC_PC_ALIGN       // pc alignment exception
        b.eq    el0_sp_pc
        cmp     x24, #ESR_ELx_EC_UNKNOWN        // unknown exception in EL0
        b.eq    el0_undef
        cmp     x24, #ESR_ELx_EC_BREAKPT_LOW    // debug exception in EL0
        b.ge    el0_dbg
        b       el0_inv
```

kernel_entry 0用于保存用户态寄存器信息(x0~x30/sp/pc/spsr等)到内核栈。

根据异常类型，
>EC == 010101
SVC instruction execution in AArch64 state.

这里是ESR_ELx_EC_SVC64, 
```c
#define ESR_ELx_EC_SVC64        (0x15)
```

将会跳转到**el0_svc**处理
```asm
/*
 * SVC handler.
 */
        .align  6
el0_svc:
        adrp    stbl, sys_call_table            // load syscall table pointer
        uxtw    scno, w8                        // syscall number in w8
        mov     sc_nr, #__NR_syscalls
el0_svc_naked:                                  // compat entry point
        stp     x0, scno, [sp, #S_ORIG_X0]      // save the original x0 and syscall number
        enable_dbg_and_irq
        ct_user_exit 1

        ldr     x16, [tsk, #TI_FLAGS]           // check for syscall hooks
        tst     x16, #_TIF_SYSCALL_WORK
        b.ne    __sys_trace
        cmp     scno, sc_nr                     // check upper syscall limit
        b.hs    ni_sys
        ldr     x16, [stbl, scno, lsl #3]       // address in the syscall table
        blr     x16                             // call sys_* routine
        b       ret_fast_syscall
ni_sys:
        mov     x0, sp
        bl      do_ni_syscall
        b       ret_fast_syscall
ENDPROC(el0_svc)
```

el0_svc流程如下
- 从**w8**中取出32bit的syscall number，扩展到64bit的**scno**，并保存到内核栈
  >PS: 感觉这里没有用， 用户态将syscall number保存到了x8, 直接使用x8即可。 这里这么实现， 可能是仿照arm的el0_svc_compat做的， 因为arm是使用w7。kernel 5.5.6的arm64已经直接使用regs->regs[8]作syscall number了)
  
- 根据**sys_call_table/scno**，获取系统调用对应的kernel实现函数**x16**，最后跳转执行
- 系统调用执行完后，从ret_fast_syscall->kernel_exit 0返回到用户态

  
### 2.2.2 系统调用表
> 源文件: kernel/arch/arm64/kernel/sys.c

sys_call_table[]的定义如下
```c
/*
 * The sys_call_table array must be 4K aligned to be accessible from
 * kernel/entry.S.
 */
void * const sys_call_table[__NR_syscalls] __aligned(4096) = {
        [0 ... __NR_syscalls - 1] = sys_ni_syscall,
#include <asm/unistd.h>
};
```

这里#include的asm/unistd.h， 最终是include/uapi/asm-generic/unistd.h
>源文件: kernel/include/uapi/asm-generic/unistd.h
```c
#define __NR3264_mmap 222
__SC_3264(__NR3264_mmap, sys_mmap2, sys_mmap)

#define __NR_mmap __NR3264_mmap
```

__SC_3264是个宏，实现如下
```c
#if __BITS_PER_LONG == 32 || defined(__SYSCALL_COMPAT)
#define __SC_3264(_nr, _32, _64) __SYSCALL(_nr, _32)
#else
#define __SC_3264(_nr, _32, _64) __SYSCALL(_nr, _64)
#endif
```

而__SYSCALL的宏定义如下
>源文件: kernel/arch/arm64/kernel/sys.c
```c
#undef __SYSCALL
#define __SYSCALL(nr, sym)      [nr] = sym,
```

也就是， __SC_3264宏会将系统调用赋值到全局数组sys_call_table[]中，每个系统调用的syscall number就是数组下标。

32bit的mmap对应
```c
[222] = sys_mmap2, 
```

64bit的mmap对应
```c
[222] = sys_mmap, 
```

最后看下sys_call_table的内容
```
crash> p sys_call_table
sys_call_table = $1 = 
 {0xffffff800821f198 <SyS_io_setup>, 0xffffff800821fbd8 <SyS_io_destroy>, 0xffffff8008220390 <SyS_io_submit>, 0xffffff80082203a8 <SyS_io_cancel>, 0xffffff8008220520 <SyS_io_getevents>, 0xffffff80081fb2e8 <SyS_setxattr>, 0xffffff80081fb308 <SyS_lsetxattr>, 0xffffff80081fb328 <SyS_fsetxattr>, 0xffffff80081fb3d8 <SyS_getxattr>, 0xffffff80081fb3f0 <SyS_lgetxattr>, 0xffffff80081fb408 <SyS_fgetxattr>, 0xffffff80081fb480 <SyS_listxattr>, 0xffffff80081fb498 <SyS_llistxattr>, 0xffffff80081fb4b0 <SyS_flistxattr>, 0xffffff80081fb518 <SyS_removexattr>, 0xffffff80081fb538 <SyS_lremovexattr>, 0xffffff80081fb558 <SyS_fremovexattr>, 0xffffff80081edcd0 <SyS_getcwd>, 0xffffff8008248de8 <SyS_lookup_dcookie>, 0xffffff800821d970 <SyS_eventfd2>, 0xffffff800821a550 <SyS_epoll_create1>, 0xffffff800821a6f0 <SyS_epoll_ctl>, 0xffffff800821b3f0 <SyS_epoll_pwait>, 0xffffff80081f2d38 <SyS_dup>, 0xffffff80081f2bc8 <SyS_dup3>, 0xffffff80081e5af8 <SyS_fcntl>, 0xffffff8008218ff8 <SyS_inotify_init1>, 0xffffff8008219180 <SyS_inotify_add_watch>, 0xffffff80082194c8 <SyS_inotify_rm_watch>, 0xffffff80081e72c0 <SyS_ioctl>, 0xffffff80083ef120 <SyS_ioprio_set>, 0xffffff80083ef3f8 <SyS_ioprio_get>, 0xffffff8008224930 <SyS_flock>, 0xffffff80081e49e0 <SyS_mknodat>, 0xffffff80081e4bf8 <SyS_mkdirat>, 0xffffff80081e4d20 <SyS_unlinkat>, 0xffffff80081e4d78 <SyS_symlinkat>, 0xffffff80081e4e70 <SyS_linkat>, 0xffffff80081e5608 <SyS_renameat>, 0xffffff80081f5d08 <SyS_umount>, 0xffffff80081f7ce8 <SyS_mount>, 0xffffff80081f7eb0 <SyS_pivot_root>, 0xffffff80080bd128 <sys_ni_syscall>, 0xffffff80082087f8 <SyS_statfs>, 0xffffff8008208890 <SyS_fstatfs>, 0xffffff80081d22a8 <SyS_truncate>, 0xffffff80081d22d8 <SyS_ftruncate>, 0xffffff80081d2308 <SyS_fallocate>, 0xffffff80081d2398 <SyS_faccessat>, 0xffffff80081d25c8 <SyS_chdir>, 0xffffff80081d2688 <SyS_fchdir>, 0xffffff80081d2720 <SyS_chroot>, 0xffffff80081d2808 <SyS_fchmod>, 0xffffff80081d2880 <SyS_fchmodat>, 0xffffff80081d2948 <SyS_fchownat>, 0xffffff80081d2ac0 <SyS_fchown>, 0xffffff80081d30e8 <SyS_openat>, 0xffffff80081d1b58 <SyS_close>, 0xffffff80081d3128 <sys_vhangup>, 0xffffff80081ddda8 <SyS_pipe2>, 0xffffff80080bd128 <sys_ni_syscall>, 0xffffff80081e7908 <SyS_getdents64>, 0xffffff80081d4070 <SyS_lseek>, 0xffffff80081d5660 <SyS_read>, 0xffffff80081d5700 <SyS_write>, 0xffffff80081d5a60 <SyS_readv>, 0xffffff80081d5a78 <SyS_writev>, 0xffffff80081d57a0 <SyS_pread64>, 0xffffff80081d5838 <SyS_pwrite64>, 0xffffff80081d5a90 <SyS_preadv>, 0xffffff80081d5ad8 <SyS_pwritev>, 0xffffff80081d5cc8 <SyS_sendfile64>, 0xffffff80081e8990 <SyS_pselect6>, 0xffffff80081e9178 <SyS_ppoll>, 0xffffff800821be68 <SyS_signalfd4>, 0xffffff8008206938 <SyS_vmsplice>, 0xffffff8008206bb8 <SyS_splice>, 0xffffff80082071b0 <SyS_tee>, 0xffffff80081d9cb0 <SyS_readlinkat>, 0xffffff80081d9c40 <SyS_newfstatat>, 0xffffff80081d9c78 <SyS_newfstat>, 0xffffff8008207800 <sys_sync>, 0xffffff8008207980 <SyS_fsync>, 0xffffff80082079a0 <SyS_fdatasync>, 0xffffff80082079c0 <SyS_sync_file_range>, 0xffffff800821cc70 <SyS_timerfd_create>, 0xffffff800821ce28 <SyS_timerfd_settime>, 0xffffff800821cee8 <SyS_timerfd_gettime>, 0xffffff8008207e08 <SyS_utimensat>, 0xffffff80080bd128 <sys_ni_syscall>, 0xffffff80080a75e0 <SyS_capget>, 0xffffff80080a7780 <SyS_capset>, 0xffffff8008088380 <SyS_arm64_personality>, 0xffffff80080a2110 <SyS_exit>, 0xffffff80080a21c0 <SyS_exit_group>, 0xffffff80080a21f8 <SyS_waitid>, 0xffffff800809c190 <SyS_set_tid_address>, 0xffffff800809c698 <SyS_unshare>, 0xffffff8008113850 <SyS_futex>, 0xffffff8008112988 <SyS_set_robust_list>, 0xffffff80081129c0 <SyS_get_robust_list>, 0xffffff80081010e0 <SyS_nanosleep>, 0xffffff80081017e8 <SyS_getitimer>, 0xffffff8008101bf0 <SyS_setitimer>, 0xffffff800811d658 <SyS_kexec_load>, 0xffffff800811ab30 <SyS_init_module>, 0xffffff80081182a0 <SyS_delete_module>, 0xffffff8008102680 <SyS_timer_create>, 0xffffff8008102b50 <SyS_timer_gettime>, 0xffffff8008102c80 <SyS_timer_getoverrun>, 0xffffff8008102cc0 <SyS_timer_settime>, 0xffffff8008102ec8 <SyS_timer_delete>, 0xffffff8008103198 <SyS_clock_settime>, 0xffffff8008103268 <SyS_clock_gettime>, 0xffffff8008103468 <SyS_clock_getres>, 0xffffff8008103550 <SyS_clock_nanosleep>, 0xffffff80080e9b20 <SyS_syslog>, 0xffffff80080a8d08 <SyS_ptrace>, 0xffffff80080c8d58 <SyS_sched_setparam>, 0xffffff80080c8d30 <SyS_sched_setscheduler>, 0xffffff80080c8fc0 <SyS_sched_getscheduler>, 0xffffff80080c9030 <SyS_sched_getparam>, 0xffffff80080c9430 <SyS_sched_setaffinity>, 0xffffff80080c9570 <SyS_sched_getaffinity>, 0xffffff80080c9628 <sys_sched_yield>, 0xffffff80080c9688 <SyS_sched_get_priority_max>, 0xffffff80080c96d0 <SyS_sched_get_priority_min>, 0xffffff80080c9718 <SyS_sched_rr_get_interval>, 0xffffff80080ad208 <sys_restart_syscall>, 0xffffff80080adcf0 <SyS_kill>, 0xffffff80080adeb8 <SyS_tkill>, 0xffffff80080ade88 <SyS_tgkill>, 0xffffff80080ae278 <SyS_sigaltstack>, 0xffffff80080aec70 <SyS_rt_sigsuspend>, 0xffffff80080ae6f0 <SyS_rt_sigaction>, 0xffffff80080ad480 <SyS_rt_sigprocmask>, 0xffffff80080ad578 <SyS_rt_sigpending>, 0xffffff80080adc00 <SyS_rt_sigtimedwait>, 0xffffff80080adef0 <SyS_rt_sigqueueinfo>, 0xffffff80080847d0 <sys_rt_sigreturn_wrapper>, 0xffffff80080af810 <SyS_setpriority>, 0xffffff80080afa38 <SyS_getpriority>, 0xffffff80080bf398 <SyS_reboot>, 0xffffff80080afc48 <SyS_setregid>, 0xffffff80080afda8 <SyS_setgid>, 0xffffff80080afe70 <SyS_setreuid>, 0xffffff80080b0048 <SyS_setuid>, 0xffffff80080b0158 <SyS_setresuid>, 0xffffff80080b0360 <SyS_getresuid>, 0xffffff80080b0480 <SyS_setresgid>, 0xffffff80080b0620 <SyS_getresgid>, 0xffffff80080b0730 <SyS_setfsuid>, 0xffffff80080b0828 <SyS_setfsgid>, 0xffffff80080b0a90 <SyS_times>, 0xffffff80080b0b08 <SyS_setpgid>, 0xffffff80080b0c90 <SyS_getpgid>, 0xffffff80080b0d10 <SyS_getsid>, 0xffffff80080b0d78 <sys_setsid>, 0xffffff80080c1498 <SyS_getgroups>, 0xffffff80080c15e0 <SyS_setgroups>, 0xffffff80080b0e68 <SyS_newuname>, 0xffffff80080b1020 <SyS_sethostname>, 0xffffff80080b11f8 <SyS_setdomainname>, 0xffffff80080b14f8 <SyS_getrlimit>, 0xffffff80080b1780 <SyS_setrlimit>, 0xffffff80080b1860 <SyS_getrusage>, 0xffffff80080b18f8 <SyS_umask>, 0xffffff80080b1928 <SyS_prctl>, 0xffffff80080b1cf0 <SyS_getcpu>, 0xffffff80080fc978 <SyS_gettimeofday>, 0xffffff80080fcb30 <SyS_settimeofday>, 0xffffff80080fcc50 <SyS_adjtimex>, 0xffffff80080b0908 <sys_getpid>, 0xffffff80080b0958 <sys_getppid>, 0xffffff80080b0980 <sys_getuid>, 0xffffff80080b09a8 <sys_geteuid>, 0xffffff80080b09d0 <sys_getgid>, 0xffffff80080b09f8 <sys_getegid>, 0xffffff80080b0930 <sys_gettid>, 0xffffff80080b1da8 <SyS_sysinfo>, 0xffffff80083a6ae0 <SyS_mq_open>, 0xffffff80083a6d00 <SyS_mq_unlink>, 0xffffff80083a6e30 <SyS_mq_timedsend>, 0xffffff80083a7120 <SyS_mq_timedreceive>, 0xffffff80083a7550 <SyS_mq_notify>, 0xffffff80083a7950 <SyS_mq_getsetattr>, 0xffffff80083a0670 <SyS_msgget>, 0xffffff80083a06a8 <SyS_msgctl>, 0xffffff80083a0e80 <SyS_msgrcv>, 0xffffff80083a0a90 <SyS_msgsnd>, 0xffffff80083a2ac0 <SyS_semget>, 0xffffff80083a2b18 <SyS_semctl>, 0xffffff80083a2dc0 <SyS_semtimedop>, 0xffffff80083a3a38 <SyS_semop>, 0xffffff80083a4eb8 <SyS_shmget>, 0xffffff80083a4ef8 <SyS_shmctl>, 0xffffff80083a55a0 <SyS_shmat>, 0xffffff80083a55c8 <SyS_shmdt>, 0xffffff8008637e90 <SyS_socket>, 0xffffff8008637f70 <SyS_socketpair>, 0xffffff80086381f8 <SyS_bind>, 0xffffff80086382a8 <SyS_listen>, 0xffffff80086384e0 <SyS_accept>, 0xffffff80086384f8 <SyS_connect>, 0xffffff80086385b0 <SyS_getsockname>, 0xffffff8008638660 <SyS_getpeername>, 0xffffff8008638710 <SyS_sendto>, 0xffffff8008638850 <SyS_recvfrom>, 0xffffff8008638988 <SyS_setsockopt>, 0xffffff8008638a58 <SyS_getsockopt>, 0xffffff8008638b08 <SyS_shutdown>, 0xffffff8008638c08 <SyS_sendmsg>, 0xffffff8008638e60 <SyS_recvmsg>, 0xffffff8008171878 <SyS_readahead>, 0xffffff800819ded8 <SyS_brk>, 0xffffff800819d228 <SyS_munmap>, 0xffffff80081a0470 <SyS_mremap>, 0xffffff80083ab868 <SyS_add_key>, 0xffffff80083aba50 <SyS_request_key>, 0xffffff80083ad218 <SyS_keyctl>, 0xffffff800809c678 <SyS_clone>, 0xffffff80081dc508 <SyS_execve>, 0xffffff8008088358 <sys_mmap>, 0xffffff80081a75c0 <SyS_fadvise64_64>, 0xffffff80081ae458 <SyS_swapon>, 0xffffff80081ade70 <SyS_swapoff>, 0xffffff800819f998 <SyS_mprotect>, 0xffffff80081a0898 <SyS_msync>, 0xffffff800819aad0 <SyS_mlock>, 0xffffff800819ab30 <SyS_munlock>, 0xffffff800819aba8 <SyS_mlockall>, 0xffffff800819ad00 <sys_munlockall>, 0xffffff80081996f8 <SyS_mincore>, 0xffffff80081a8138 <SyS_madvise>, 0xffffff800819ea08 <SyS_remap_file_pages>, 0xffffff80080bd128 <sys_ni_syscall>, 0xffffff80080bd128 <sys_ni_syscall>, 0xffffff80080bd128 <sys_ni_syscall>, 0xffffff80080bd128 <sys_ni_syscall>, 0xffffff80080bd128 <sys_ni_syscall>, 0xffffff80080adfd8 <SyS_rt_tgsigqueueinfo>, 0xffffff800815cc48 <SyS_perf_event_open>, 0xffffff8008638328 <SyS_accept4>, 0xffffff80086390b8 <SyS_recvmmsg>, 0xffffff80080bd128 <sys_ni_syscall>, 0xffffff80080bd128 <sys_ni_syscall>, 0xffffff80080bd128 <sys_ni_syscall>, 0xffffff80080bd128 <sys_ni_syscall>, 0xffffff80080bd128 <sys_ni_syscall>, 0xffffff80080bd128 <sys_ni_syscall>, 0xffffff80080bd128 <sys_ni_syscall>, 0xffffff80080bd128 <sys_ni_syscall>, 0xffffff80080bd128 <sys_ni_syscall>, 0xffffff80080bd128 <sys_ni_syscall>, 0xffffff80080bd128 <sys_ni_syscall>, 0xffffff80080bd128 <sys_ni_syscall>...}

crash> p sizeof(sys_call_table)/sizeof(sys_call_table[0])
$2 = 291

crash> p sys_call_table[222]
$3 = (void * const) 0xffffff8008088358 <sys_mmap>
```

### 2.2.3 sys_mmap实现

>源文件: kernel/arch/arm64/kernel/sys.c
```c
asmlinkage long sys_mmap(unsigned long addr, unsigned long len,
                         unsigned long prot, unsigned long flags,
                         unsigned long fd, off_t off)
{
        if (offset_in_page(off) != 0)
                return -EINVAL;

        return sys_mmap_pgoff(addr, len, prot, flags, fd, off >> PAGE_SHIFT);
}
```

kernel源码中搜索不到sys_mmap_pgoff()实现， 原因是kernel针对该函数用宏进行了封装。
>源文件: kernel/mm/mmap.c
```c
SYSCALL_DEFINE6(mmap_pgoff, unsigned long, addr, unsigned long, len, 
                unsigned long, prot, unsigned long, flags,
                unsigned long, fd, unsigned long, pgoff)
{
    ... ...
}
```

**SYSCALL_DEFINE6**的实现如下
>源文件: kernel/include/linux/syscalls.h
```c
#define SYSCALL_DEFINE6(name, ...) SYSCALL_DEFINEx(6, _##name, __VA_ARGS__)

#define SYSCALL_DEFINEx(x, sname, ...)                          \
        SYSCALL_METADATA(sname, x, __VA_ARGS__)                 \
        __SYSCALL_DEFINEx(x, sname, __VA_ARGS__)


#define __SYSCALL_DEFINEx(x, name, ...)                                 \
        asmlinkage long sys##name(__MAP(x,__SC_DECL,__VA_ARGS__))       \
                __attribute__((alias(__stringify(SyS##name))));         \
        static inline long SYSC##name(__MAP(x,__SC_DECL,__VA_ARGS__));  \
        asmlinkage long SyS##name(__MAP(x,__SC_LONG,__VA_ARGS__));      \
        asmlinkage long SyS##name(__MAP(x,__SC_LONG,__VA_ARGS__))       \
        {                                                               \
                long ret = SYSC##name(__MAP(x,__SC_CAST,__VA_ARGS__));  \
                __MAP(x,__SC_TEST,__VA_ARGS__);                         \
                __PROTECT(x, ret,__MAP(x,__SC_ARGS,__VA_ARGS__));       \
                return ret;                                             \
        }                                                               \
        static inline long SYSC##name(__MAP(x,__SC_DECL,__VA_ARGS__))
```

# 3. 总结
- 执行系统调用时， 用户态切换到内核态，保存用户态现场信息。系统调用执行完后，内核态返回用户态，恢复用户态现场信息
- 不同平台的syscall number是不同的，即使arm和arm64也不相同
- 每个系统调用xxx，在内核中都有对应的sys_xxx实现

---

![程序员自我修养](http://ww1.sinaimg.cn/large/005Kyrj9ly1gbvsonijdoj3076076wex.jpg)

<center>
程序员自我修养(ID: dumphex)
</center>

---
