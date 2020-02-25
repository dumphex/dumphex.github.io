---
title: SegmentFault处理流程
date: 2020-02-25 13:51:49
tags:
- SegmentFault
- arm64
- kernel
categories: Linux

---

本文将基于一个简单的用户态段错误问题，简单梳理下arm64平台SegmentFault处理流程。

<!-- more -->

# 1. demo

## 1.1 运行环境 
- Linux + arm64平台
- kernel 4.9
- gcc version 6.3.1 20170404 (Linaro GCC 6.3-2017.05)

## 1.2 测试程序(el0_da.c)
```C
#include <stddef.h>

int main(int argc, char *argv[]) {
  char *p = NULL;

  *p = 1; 

  return 0;
}
```

反汇编如下
```asm
0000000000000000 <main>:
   0:	d10083ff 	sub	sp, sp, #0x20
   4:	b9000fe0 	str	w0, [sp,#12]
   8:	f90003e1 	str	x1, [sp]
   c:	f9000fff 	str	xzr, [sp,#24]
  10:	f9400fe0 	ldr	x0, [sp,#24]
  14:	52800021 	mov	w1, #0x1                   	// #1
  18:	39000001 	strb	w1, [x0]
  1c:	52800000 	mov	w0, #0x0                   	// #0
  20:	910083ff 	add	sp, sp, #0x20
  24:	d65f03c0 	ret
```

## 1.3 运行结果

```bash
./run.sh: line 9:  1131 Segmentation fault      (core dumped) ./el0_da
```

dmesg打印的kenrel log如下
```
$ dmesg -c
[  720.577925] [1] el0_da[1131]: unhandled level 1 translation fault (11) at 0x00000000, esr 0x92000045
[  720.587064] [1] pgd = ffffffc274af0000
[  720.590821] [1] [00000000] *pgd=0000000000000000
[  720.595271] [1] , *pud=0000000000000000
[  720.599104] [1] 
[  720.600942] [1] 
[  720.602778] [1] CPU: 1 PID: 1131 Comm: el0_da Not tainted 4.9.38-timchip-v4.3.0-00361-gd5024dc9d6f5 #1
[  720.611989] [1] Hardware name: linux,dummy-virt (DT)
[  720.616951] [1] task: ffffffc26c9fb000 task.stack: ffffffc276cf8000
[  720.623216] [1] PC is at 0x5593dfa800
[  720.626876] [1] LR is at 0x7f7dd27364
[  720.630537] [1] pc : [<0000005593dfa800>] lr : [<0000007f7dd27364>] pstate: 60000000
[  720.638273] [1] sp : 0000007fcc5b8590
[  720.641932] [1] x29: 0000007fcc5b85b0 x28: 0000000000000000 
[  720.647611] [1] x27: 0000000000000000 x26: 0000000000000000 
[  720.653287] [1] x25: 0000000000000000 x24: 0000000000000000 
[  720.658963] [1] x23: 0000000000000000 x22: 0000000000000000 
[  720.664643] [1] x21: 0000005593dfa6a0 x20: 0000000000000000 
[  720.670319] [1] x19: 0000005593dfa810 x18: 0000000000040926 
[  720.675998] [1] x17: 0000005593e0b008 x16: 0000007f7dd27288 
[  720.681675] [1] x15: 000000000000080d x14: 0000000000000000 
[  720.687351] [1] x13: 0000007f7de80028 x12: 0000007f7de80030 
[  720.693030] [1] x11: 0000040000000000 x10: 0101010101010101 
[  720.698706] [1] x9 : 03ffffffffffffff x8 : ffffffffffffffff 
[  720.704385] [1] x7 : 0000040000000000 x6 : 0000000000000000 
[  720.710061] [1] x5 : 0000000000000000 x4 : 0000007fcc5b8608 
[  720.715740] [1] x3 : 0000005593dfa7e8 x2 : 0000007fcc5b86f8 
[  720.721416] [1] x1 : 0000000000000001 x0 : 0000000000000000 
[  720.727091] [1] 
```
    
# 2. 处理流程

## 2.1 page fault
- 用户态进程访问了非法地址后， CPU的MMU无法完成虚拟地址到物理地址的转换，从而产生page fault异常。
- 此后，由**用户态**切换到**内核态**。

## 2.2 异常向量表
- 源码位于arch/arm64/kernel/entry.S
- 用户态触发的访问内存异常， 最终会进入到异常向量表的el0_sync

el0_sync如下
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

这里简单解释下
- kernel_entry: 构造pt_regs相关的数据(包括通用目的寄存器，sp, pc等)，保存到当前内核栈
- esr_el1是异常诊断寄存器，用于存储跳转EL1的异常相关信息
![ESR](http://ww1.sinaimg.cn/large/006CVPwLly1ga7sduhkiij30tu0ho3zl.jpg)
  
高6位是exception class, 用于标识当前异常的类型

根据前面的测试用例，esr值为0x92000045，则exception class= esr >> 26 = 0x24, 对应ESR_ELx_EC_DABT_LOW
```
#define ESR_ELx_EC_DABT_LOW     (0x24)
```

会跳到el0_da继续处理，el0_da的实现如下
```
el0_da:
	/*
	 * Data abort handling
	 */
	mrs	x26, far_el1
	// enable interrupts before calling the main handler
	enable_dbg_and_irq
	ct_user_exit
	clear_address_tag x0, x26
	mov	x1, x25
	mov	x2, sp
	bl	do_mem_abort
	b	ret_to_user
el0_ia:
```

el0_da的操作
- do_mem_abort()
  - far_el1是出错的内存地址，保存到x0
  - x25是esr_el1，保存到x1
  - sp是保存的struct pt_regs基地址，保存到x2

- ret_to_user()
  - 调用kernel_exit 0, 最终返回用户态。

## 2.3 do_mem_abort
源码位于arch/arm64/mm/fault.c
```
/*
 * Dispatch a data abort to the relevant handler.
 */
asmlinkage void __exception do_mem_abort(unsigned long addr, unsigned int esr,
					 struct pt_regs *regs)
{
	const struct fault_info *inf = esr_to_fault_info(esr);
	struct siginfo info;

	if (!inf->fn(addr, esr, regs))
		return;

	pr_alert("Unhandled fault: %s (0x%08x) at 0x%016lx\n",
		 inf->name, esr, addr);

	info.si_signo = inf->sig;
	info.si_errno = 0;
	info.si_code  = inf->code;
	info.si_addr  = (void __user *)addr;
	arm64_notify_die("", regs, &info, esr);
}
```

esr_to_fault_info()函数用于从esr的低6bit取出**错误状态码DFSC(Data Fault Status Code)**

|DFSC|说明|
|----|----|
|000000|Address size fault, level 0 of translation or translation table base register|
|000001|Address size fault, level 1|
|000010|Address size fault, level 2|
|000011|Address size fault, level 3|
|000100|Translation fault, level 0|
|000101|Translation fault, level 1|
|000110|Translation fault, level 2|
|000111|Translation fault, level 3|
|001001|Access flag fault, level 1|
|001010|Access flag fault, level 2|
|001011|Access flag fault, level 3|
|001101|Permission fault, level 1|
|001110|Permission fault, level 2|
|001111|Permission fault, level 3|
|010000|Synchronous External abort, not on translation table walk|
|011000|Synchronous parity or ECC error on memory access, not on translation table walk|
|010100|Synchronous External abort, on translation table walk, level 0|
|010101|Synchronous External abort, on translation table walk, level 1|
|010110|Synchronous External abort, on translation table walk, level 2|
|010111|Synchronous External abort, on translation table walk, level 3|
|011100|Synchronous parity or ECC error on memory access on translation table walk, level 0|
|011101|Synchronous parity or ECC error on memory access on translation table walk, level 1|
|011110|Synchronous parity or ECC error on memory access on translation table walk, level 2|
|011111|Synchronous parity or ECC error on memory access on translation table walk, level 3|
|100001|Alignment fault|
|110000|TLB conflict abort|
|110001|Unsupported atomic hardware update fault, if the implementation includes ARMv8.1-TTHM. Otherwise reserved.|
|110100|IMPLEMENTATION DEFINED fault (Lockdown)|
|110101|IMPLEMENTATION DEFINED fault (Unsupported Exclusive or Atomic access)|
|111101|Section Domain Fault, used only for faults reported in the PAR_EL1|
|111110|Page Domain Fault, used only for faults reported in the PAR_EL1|

而fault_info[]是一个struct fault_info结构体数组，对应这64种错误状态码的处理
```
static const struct fault_info fault_info[] = { 
        { do_bad,               SIGBUS,  0,             "ttbr address size fault"       },
        { do_bad,               SIGBUS,  0,             "level 1 address size fault"    },  
        { do_bad,               SIGBUS,  0,             "level 2 address size fault"    },  
        { do_bad,               SIGBUS,  0,             "level 3 address size fault"    },  
        { do_translation_fault, SIGSEGV, SEGV_MAPERR,   "level 0 translation fault"     },  
        { do_translation_fault, SIGSEGV, SEGV_MAPERR,   "level 1 translation fault"     },  
        { do_translation_fault, SIGSEGV, SEGV_MAPERR,   "level 2 translation fault"     },  
        { do_page_fault,        SIGSEGV, SEGV_MAPERR,   "level 3 translation fault"     },  
        { do_bad,               SIGBUS,  0,             "unknown 8"                     },
        { do_page_fault,        SIGSEGV, SEGV_ACCERR,   "level 1 access flag fault"     },  
        { do_page_fault,        SIGSEGV, SEGV_ACCERR,   "level 2 access flag fault"     },  
        { do_page_fault,        SIGSEGV, SEGV_ACCERR,   "level 3 access flag fault"     },  
        { do_bad,               SIGBUS,  0,             "unknown 12"                    },
        { do_page_fault,        SIGSEGV, SEGV_ACCERR,   "level 1 permission fault"      },  
        { do_page_fault,        SIGSEGV, SEGV_ACCERR,   "level 2 permission fault"      },  
        { do_page_fault,        SIGSEGV, SEGV_ACCERR,   "level 3 permission fault"      },  
        { do_bad,               SIGBUS,  0,             "synchronous external abort"    },  
        { do_bad,               SIGBUS,  0,             "unknown 17"                    },
        { do_bad,               SIGBUS,  0,             "unknown 18"                    },
        { do_bad,               SIGBUS,  0,             "unknown 19"                    },
        { do_bad,               SIGBUS,  0,             "synchronous external abort (translation table walk)" },
        { do_bad,               SIGBUS,  0,             "synchronous external abort (translation table walk)" },
        { do_bad,               SIGBUS,  0,             "synchronous external abort (translation table walk)" },
        { do_bad,               SIGBUS,  0,             "synchronous external abort (translation table walk)" },
        { do_bad,               SIGBUS,  0,             "synchronous parity error"      },  
        { do_bad,               SIGBUS,  0,             "unknown 25"                    },
        { do_bad,               SIGBUS,  0,             "unknown 26"                    },
        { do_bad,               SIGBUS,  0,             "unknown 27"                    },
        { do_bad,               SIGBUS,  0,             "synchronous parity error (translation table walk)" },
        { do_bad,               SIGBUS,  0,             "synchronous parity error (translation table walk)" },
        { do_bad,               SIGBUS,  0,             "synchronous parity error (translation table walk)" },
        { do_bad,               SIGBUS,  0,             "synchronous parity error (translation table walk)" },
        { do_bad,               SIGBUS,  0,             "unknown 32"                    },
        { do_alignment_fault,   SIGBUS,  BUS_ADRALN,    "alignment fault"               },
        { do_bad,               SIGBUS,  0,             "unknown 34"                    },
        { do_bad,               SIGBUS,  0,             "unknown 35"                    },
        { do_bad,               SIGBUS,  0,             "unknown 36"                    },
        { do_bad,               SIGBUS,  0,             "unknown 37"                    },
        { do_bad,               SIGBUS,  0,             "unknown 38"                    },
        { do_bad,               SIGBUS,  0,             "unknown 39"                    },
        { do_bad,               SIGBUS,  0,             "unknown 40"                    },
        { do_bad,               SIGBUS,  0,             "unknown 41"                    },
        { do_bad,               SIGBUS,  0,             "unknown 42"                    },
        { do_bad,               SIGBUS,  0,             "unknown 43"                    },
        { do_bad,               SIGBUS,  0,             "unknown 44"                    },
        { do_bad,               SIGBUS,  0,             "unknown 45"                    },
        { do_bad,               SIGBUS,  0,             "unknown 46"                    },
        { do_bad,               SIGBUS,  0,             "unknown 47"                    },
        { do_bad,               SIGBUS,  0,             "TLB conflict abort"            },
        { do_bad,               SIGBUS,  0,             "unknown 49"                    },
        { do_bad,               SIGBUS,  0,             "unknown 50"                    },
        { do_bad,               SIGBUS,  0,             "unknown 51"                    },
        { do_bad,               SIGBUS,  0,             "implementation fault (lockdown abort)" },
        { do_bad,               SIGBUS,  0,             "implementation fault (unsupported exclusive)" },
        { do_bad,               SIGBUS,  0,             "unknown 54"                    },
        { do_bad,               SIGBUS,  0,             "unknown 55"                    },
        { do_bad,               SIGBUS,  0,             "unknown 56"                    },
        { do_bad,               SIGBUS,  0,             "unknown 57"                    },
        { do_bad,               SIGBUS,  0,             "unknown 58"                    },
        { do_bad,               SIGBUS,  0,             "unknown 59"                    },
        { do_bad,               SIGBUS,  0,             "unknown 60"                    },
        { do_bad,               SIGBUS,  0,             "section domain fault"          },
        { do_bad,               SIGBUS,  0,             "page domain fault"             },
        { do_bad,               SIGBUS,  0,             "unknown 63"                    },
};
```

dfsc = esr & 0x3f = 0x92000045 & 0x3f = 0x5, 对应fault_info[]中的第5个元素"level 1 translation fault"，下一步会跳到do_translation_fault()处理。
    
## 2.4 do_translation_fault
```
/*
 * First Level Translation Fault Handler
 *
 * We enter here because the first level page table doesn't contain a valid
 * entry for the address.
 *
 * If the address is in kernel space (>= TASK_SIZE), then we are probably
 * faulting in the vmalloc() area.
 *
 * If the init_task's first level page tables contains the relevant entry, we
 * copy the it to this task.  If not, we send the process a signal, fixup the
 * exception, or oops the kernel.
 *
 * NOTE! We MUST NOT take any locks for this case. We may be in an interrupt
 * or a critical region, and should only copy the information from the master
 * page table, nothing more.
 */
static int __kprobes do_translation_fault(unsigned long addr,
					  unsigned int esr,
					  struct pt_regs *regs)
{
	if (addr < TASK_SIZE)
		return do_page_fault(addr, esr, regs);

	do_bad_area(addr, esr, regs);
	return 0;
}
```

这里会跳到do_page_fault()

## 2.5 do_page_fault
do_page_fault()主要会调用
- __do_page_fault()
- __do_user_fault()

__do_page_fault()的实现如下
```
static int __do_page_fault(struct mm_struct *mm, unsigned long addr,
                           unsigned int mm_flags, unsigned long vm_flags,
                           struct task_struct *tsk)
{
        struct vm_area_struct *vma;
        int fault;

        vma = find_vma(mm, addr);
        fault = VM_FAULT_BADMAP;
        if (unlikely(!vma))
                goto out;
        if (unlikely(vma->vm_start > addr))
                goto check_stack;

        /*
         * Ok, we have a good vm_area for this memory access, so we can handle
         * it.
         */
good_area:
        /*
         * Check that the permissions on the VMA allow for the fault which
         * occurred.
         */
        if (!(vma->vm_flags & vm_flags)) {
                fault = VM_FAULT_BADACCESS;
                goto out;
        }

        return handle_mm_fault(vma, addr & PAGE_MASK, mm_flags);

check_stack:
        if (vma->vm_flags & VM_GROWSDOWN && !expand_stack(vma, addr))
                goto good_area;
out:
        return fault;
}
```
__do_page_fault()这里， 没有找到相应的vma， 则会直接返回。

前面的page fault无法处理后， 若是用户态page fault，最终会走到__do_user_fault()

## 2.6 __do_user_fault
```
static void __do_user_fault(struct task_struct *tsk, unsigned long addr,
                            unsigned int esr, unsigned int sig, int code,
                            struct pt_regs *regs)
{
        struct siginfo si;
        const struct fault_info *inf;
                
        if (unhandled_signal(tsk, sig) && show_unhandled_signals_ratelimited()) {
                inf = esr_to_fault_info(esr);
                pr_info("%s[%d]: unhandled %s (%d) at 0x%08lx, esr 0x%03x\n",
                        tsk->comm, task_pid_nr(tsk), inf->name, sig,
                        addr, esr);
                show_pte(tsk->mm, addr);
                show_regs(regs);
        }

        tsk->thread.fault_address = addr;
        tsk->thread.fault_code = esr;
        si.si_signo = sig;
        si.si_errno = 0;
        si.si_code = code;
        si.si_addr = (void __user *)addr;
        force_sig_info(sig, &si, tsk);
}
```

__do_user_fault()主要做几件事:

### 2.6.1 打印出错进程信息
```
el0_da[1131]: unhandled level 1 translation fault (11) at 0x00000000, esr 0x92000045
```

### 2.6.2  show_pte()
- 打印pgd/pud/pmd等信息
```
/*
 * Dump out the page tables associated with 'addr' in mm 'mm'.
 */
void show_pte(struct mm_struct *mm, unsigned long addr)
{
        pgd_t *pgd;

        if (!mm)
                mm = &init_mm;

        pr_alert("pgd = %p\n", mm->pgd);
        pgd = pgd_offset(mm, addr);
        pr_alert("[%08lx] *pgd=%016llx", addr, pgd_val(*pgd));

        do {
                pud_t *pud;
                pmd_t *pmd;
                pte_t *pte;

                if (pgd_none(*pgd) || pgd_bad(*pgd))
                        break;

                pud = pud_offset(pgd, addr);
                printk(", *pud=%016llx", pud_val(*pud));
                if (pud_none(*pud) || pud_bad(*pud))
                        break;

                pmd = pmd_offset(pud, addr);
                printk(", *pmd=%016llx", pmd_val(*pmd));
                if (pmd_none(*pmd) || pmd_bad(*pmd))
                        break;

                pte = pte_offset_map(pmd, addr);
                printk(", *pte=%016llx", pte_val(*pte));
                pte_unmap(pte);
        } while(0);

        printk("\n");
}
```

### 2.6.3 show_regs()
- 源码位于arch/arm64/kernel/process.c
- 打印PC/LR/SP/通用目的寄存器等
```
void __show_regs(struct pt_regs *regs)
{
        int i, top_reg;
        u64 lr, sp;

        if (compat_user_mode(regs)) {
                lr = regs->compat_lr;
                sp = regs->compat_sp;
                top_reg = 12;
        } else {
                lr = regs->regs[30];
                sp = regs->sp;
                top_reg = 29;
        }

        show_regs_print_info(KERN_DEFAULT);
        print_symbol("PC is at %s\n", instruction_pointer(regs));
        print_symbol("LR is at %s\n", lr);
        printk("pc : [<%016llx>] lr : [<%016llx>] pstate: %08llx\n",
               regs->pc, lr, regs->pstate);
        printk("sp : %016llx\n", sp);

        i = top_reg;

        while (i >= 0) {
                printk("x%-2d: %016llx ", i, regs->regs[i]);
                i--;

                if (i % 2 == 0) {
                        pr_cont("x%-2d: %016llx ", i, regs->regs[i]);
                        i--;
                }

                pr_cont("\n");
        }
        printk("\n");
}

void show_regs(struct pt_regs * regs)
{
        printk("\n");
        __show_regs(regs);
}
```

show_regs_print_info()相关
- 源码位于kernel/printk/printk.c
- 用于打印通用的debug信息
```
void dump_stack_print_info(const char *log_lvl)
{
        printk("%sCPU: %d PID: %d Comm: %.20s %s %s %.*s\n",
               log_lvl, raw_smp_processor_id(), current->pid, current->comm,
               print_tainted(), init_utsname()->release,
               (int)strcspn(init_utsname()->version, " "),
               init_utsname()->version);

        if (dump_stack_arch_desc_str[0] != '\0')
                printk("%sHardware name: %s\n",
                       log_lvl, dump_stack_arch_desc_str);

        print_worker_info(log_lvl, current);
}

/**
 * show_regs_print_info - print generic debug info for show_regs()
 * @log_lvl: log level
 *
 * show_regs() implementations can use this function to print out generic
 * debug information.
 */
void show_regs_print_info(const char *log_lvl)
{
        dump_stack_print_info(log_lvl);

        printk("%stask: %p task.stack: %p\n",
               log_lvl, current, task_stack_page(current));
}
```

### 2.6.4 force_sig_info()
- 源码位于source/kernel/signal.c
- 用于向进程发送信号信息

```
/*
 * Force a signal that the process can't ignore: if necessary
 * we unblock the signal and change any SIG_IGN to SIG_DFL.
 *
 * Note: If we unblock the signal, we always reset it to SIG_DFL,
 * since we do not want to have a signal handler that was blocked
 * be invoked when user space had explicitly blocked it.
 *
 * We don't want to have recursive SIGSEGV's etc, for example,
 * that is why we also clear SIGNAL_UNKILLABLE.
 */
int
force_sig_info(int sig, struct siginfo *info, struct task_struct *t)
{
	unsigned long int flags;
	int ret, blocked, ignored;
	struct k_sigaction *action;

	spin_lock_irqsave(&t->sighand->siglock, flags);
	action = &t->sighand->action[sig-1];
	ignored = action->sa.sa_handler == SIG_IGN;
	blocked = sigismember(&t->blocked, sig);
	if (blocked || ignored) {
		action->sa.sa_handler = SIG_DFL;
		if (blocked) {
			sigdelset(&t->blocked, sig);
			recalc_sigpending_and_wake(t);
		}
	}
	if (action->sa.sa_handler == SIG_DFL)
		t->signal->flags &= ~SIGNAL_UNKILLABLE;
	ret = specific_send_sig_info(sig, info, t);
	spin_unlock_irqrestore(&t->sighand->siglock, flags);

	return ret;
}

static int
specific_send_sig_info(int sig, struct siginfo *info, struct task_struct *t)
{
	return send_signal(sig, info, t, 0);
}
```

# 3. 总结
- 本文通过简单例子，分析SegmentFault的处理流程
- 针对SegmentFault问题，可以借助gdb在线分析进程或离线分core dump等，来定位具体出错的地方。

---

![程序员自我修养](http://ww1.sinaimg.cn/large/005Kyrj9ly1gbvsonijdoj3076076wex.jpg)

<center>
程序员自我修养(ID: dumphex)
</center>

---
