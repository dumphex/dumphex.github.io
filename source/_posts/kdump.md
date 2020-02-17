---
title: 深入学习kdump原理
date: 2020-02-15 18:00:00
modified: 2020-02-17 10:06:00
tags:
- kernel
- kdump
- crash
categories: kernel
---

本文将深入学习kdump相关代码，梳理kdump整个流程。

<!-- more -->



# Overview



## 什么是kdump

- kernel崩溃时， 创建核心存储(core dump)

- kdump导出/proc/vmcore，便于离线分析crash原因

  

## kernel的分类

- first kernel(production kernel)

- second kernel(dump-capture kernel)

  

## kdump流程

![kdump_sub.png](http://ww1.sinaimg.cn/large/006CVPwLly1g9ac5zupkdj30qp0hbac4.jpg)







## 版本信息

- kernel版本是4.9.38
- kexec-tools版本是v2.0.16
- architecture是arm64



# kexec

## kexec overview

### kexec功能

kexec主要有两个功能

- 快速切换kernel

- kdump

  

### 代码下载/编译

kexec可通过github下载

```shell
$ git clone https://github.com/horms/kexec-tools.git
```



下载仓库后， 可交叉编译出arm64可执行文件

```shell
$ ./bootstrap
$ mkdir timzhang
$ ./configure --prefix=/home/timzhang/work/project/github/kexec-tools/timzhang --build=x86_64-linux-gnu --host=aarch64-linux-gnu  --target=aarch64-linux-gnu
$ make
$ make install
```



### kexec运行

- 快速切换kernel

```shell
$ sudo ./kexec -l ./Image --initrd=kdump.cpio --dtb=./chip_asic.dtb --append="1 maxcpus=1 reset_devices console=ttyS0,115200 earlycon debug user_debug=31 loglevel=10"

$ sudo ./kexec -e
```



- kdump

```shell
$ sudo ./kexec -p ./Image --initrd=./kdump.cpio --dtb=./chip_asic.dtb --append="1 maxcpus=1 reset_devices console=ttyS0,115200 earlycon debug user_debug=31 loglevel=10"
```

> 注: Image和dtb文件最好和当前kernel版本保持一致！



## kexec用户态

### 配置解析

判断是否加载crashkernel， 相关函数实现在**is_crashkernel_mem_reserved**()

该函数主要操作如下

- 读取/proc/iomem
- 调用回调函数， 处理Crash kernel/System RAM/Kernel code/Kernel data等感兴趣的内存部分.

```shell
# cat /proc/iomem 
... ...
105100000-2ffffffff : System RAM
300020000-3ffffffff : System RAM
  300080000-300aaffff : Kernel code
  300b40000-300c85fff : Kernel data
  310000000-313ffffff : Crash kernel
408000000-4ffffffff : System RAM
```



其中， 除了crash kernel部分， System RAM其余部分都是需要被dump的。

![memory.jpg](http://ww1.sinaimg.cn/large/006CVPwLly1g9cx07tykjj30qo0k0754.jpg)

### 收集segment

kexec用户态的信息， 存储在**struct kexec_info**里面。 

struct kexec_info结构体的定义如下:

```c
struct kexec_info {
        struct kexec_segment *segment;
        int nr_segments;
        struct memory_range *memory_range;
        int memory_ranges;
        struct memory_range *crash_range;
        int nr_crash_ranges;
        void *entry;
        struct mem_ehdr rhdr;
        unsigned long backup_start;
        unsigned long kexec_flags;
        unsigned long backup_src_start;
        unsigned long backup_src_size;
        /* Set to 1 if we are using kexec file syscall */
        unsigned long file_mode :1; 

        /* Filled by kernel image processing code */
        int initrd_fd;
        char *command_line;
        int command_line_len;
};
```



kexec在用户态， 主要是集齐5个segment, 它们分别是

- kernel segment

- ELF core header segment

- initrd segment

- dtb segment

- purgatory segment

  

#### kernel segment

**功能**: 读取kexec运行时指定的kernel image

| file type | probe              | load              | usage              |
| --------- | ------------------ | ----------------- | ------------------ |
| vmlinux   | elf_arm64_probe    | elf_arm64_load    | elf_arm64_usage    |
| Image     | image_arm64_probe  | image_arm64_load  | image_arm64_usage  |
| uImage    | uImage_arm64_probe | uImage_arm64_load | uImage_arm64_usage |



#### ELF core header segment

**功能**: 为kdump生成vmcore准备ELF core header



构造ELF core header segment时， 主要构造了ELF header和program header

其中， program header包含了PT_NOTE和PT_LOAD两类

| program header 类型 | 内容                          |
| ------------------- | ----------------------------- |
| PT_NOTE             | cpu, vmcoreinfo               |
| PT_LOAD             | kernel text, system ram chunk |

构造结束后， 将ELF core header的起始地址保存到**elfcorehdr_mem**



#### initrd segment

**功能**: 读取kexec运行时指定的initrd



#### dtb segment

**功能**: 读取kexec运行时指定的dtb

设置属性

- **"linux,elfcorehdr"**: 将ELF core header地址(**elfcorehdr_mem**)设置到此属性

- **"linux,usable-memory-range"**: 将**crash_reserved_mem**设置到此属性(指定capture kernel的总内存大小)

  

#### purgatory segment

**功能**: 用于完成crash kernel完整性校验和kernel跳转

主要流程如下

- purgatory相关源文件生成purgatory.ro
- bin-to-hex将purgatory.ro转换成purgatory.c(ELF内容格式到purgatory[])
- purgatory.c和其它源文件编译生成kexec可执行程序
- kexec在运行过程中， 构造purgatory可重定位对象，放到purgatory buffer



purgatory.ro中有重要的三个符号

| 符号               | 说明                                       |
| ------------------ | ------------------------------------------ |
| purgatory_start    | purgatory的启动地址, 保存到info->entry字段 |
| arm64_kernel_entry | capture kernel代码段首地址                 |
| arm64_dtb_addr     | capture kernel依赖的dtb地址                |



```shell
$ aarch64-linux-gnu-readelf -s purgatory.ro.sym |grep -e purgatory_start -e arm64_
    66: 0000000000000120     8 NOTYPE  GLOBAL DEFAULT    4 arm64_kernel_entry
    68: 0000000000000660    36 NOTYPE  GLOBAL DEFAULT    1 purgatory_start
    69: 0000000000000128     8 NOTYPE  GLOBAL DEFAULT    4 arm64_dtb_addr
```

#### 小结

5个segment收集完毕后， info.segment[]的布局如下



![kexec_info_segment_01.jpg](http://ww1.sinaimg.cn/large/006CVPwLly1g9bq9vje9wj30qo0k0q3t.jpg)

### 更新哈希值

调用update_purgatory()， 计算除了purgatory之外其它4个segment的sha256值, 并存储到**sha256_digest**符号

```shell
$ aarch64-linux-gnu-readelf -s purgatory.ro.sym |grep -e " sha256_regions" -e " sha256_digest"
    56: 0000000000000000   256 OBJECT  GLOBAL DEFAULT    4 sha256_regions
    57: 0000000000000100    32 OBJECT  GLOBAL DEFAULT    4 sha256_digest
```



### 开始加载

kexex通过kexec_load函数中的系统调用来完成最后的加载。

```c
static inline long kexec_load(void *entry, unsigned long nr_segments,
                        struct kexec_segment *segments, unsigned long flags)
{
        return (long) syscall(__NR_kexec_load, entry, nr_segments, segments, flags);
}
```



## kexec内核态

### crashkernel

crashkernel表示给capture kernel预留的内存.

在打开kdump的kernel中， 会有类似如下的启动log

```
... ...
crashkernel reserved: 0x0000000310000000 - 0x0000000314000000 (64 MB)
... ...
Kernel command line: console=ttyS0,115200 earlycon user_debug=31 crashkernel=64M@0x310000000
... ...
```

这里给capture  kernel配置的起始物理地址0x310000000, 大小为64MB.



具体在kernel代码中， 是通过**reserve_crashkernel**()来完成的

```c
static void __init reserve_crashkernel(void)
{
        unsigned long long crash_base, crash_size;
        int ret;

        ret = parse_crashkernel(boot_command_line, memblock_phys_mem_size(),
                                &crash_size, &crash_base);
        /* no crashkernel= or invalid value specified */
        if (ret || !crash_size)
                return;

        crash_size = PAGE_ALIGN(crash_size);

        if (crash_base == 0) {
                /* Current arm64 boot protocol requires 2MB alignment */
                crash_base = memblock_find_in_range(0, ARCH_LOW_ADDRESS_LIMIT,
                                crash_size, SZ_2M);
                if (crash_base == 0) {
                        pr_warn("cannot allocate crashkernel (size:0x%llx)\n",
                                crash_size);
                        return;
                }
        } else {
                /* User specifies base address explicitly. */
                if (!memblock_is_region_memory(crash_base, crash_size)) {
                        pr_warn("cannot reserve crashkernel: region is not memory\n");
                        return;
                }

                if (memblock_is_region_reserved(crash_base, crash_size)) {
                        pr_warn("cannot reserve crashkernel: region overlaps reserved memory\n");
                        return;
                }

                if (!IS_ALIGNED(crash_base, SZ_2M)) {
                        pr_warn("cannot reserve crashkernel: base address is not 2MB aligned\n");
                        return;
                }
        }
        memblock_reserve(crash_base, crash_size);

        pr_info("crashkernel reserved: 0x%016llx - 0x%016llx (%lld MB)\n",
                crash_base, crash_base + crash_size, crash_size >> 20);

        crashk_res.start = crash_base;
        crashk_res.end = crash_base + crash_size - 1;
}
```

内核态是通过解析boot_command_line来获取crashkernel的起始地址和大小，并保存到**crashk_res**结构体中。



### sys_kexec_load

kexec在用户态调用**NR_kexec_load(104)**的系统调用后，最终会执行到kernel态的sys_kexec_load

```c
SYSCALL_DEFINE4(kexec_load, unsigned long, entry, unsigned long, nr_segments,
                struct kexec_segment __user *, segments, unsigned long, flags)
{
        int result;

        /* We only trust the superuser with rebooting the system. */
        if (!capable(CAP_SYS_BOOT) || kexec_load_disabled)
                return -EPERM;

        /*  
         * Verify we have a legal set of flags
         * This leaves us room for future extensions.
         */
        if ((flags & KEXEC_FLAGS) != (flags & ~KEXEC_ARCH_MASK))
                return -EINVAL;

        /* Verify we are on the appropriate architecture */
        if (((flags & KEXEC_ARCH_MASK) != KEXEC_ARCH) &&
                ((flags & KEXEC_ARCH_MASK) != KEXEC_ARCH_DEFAULT))
                return -EINVAL;

        /* Put an artificial cap on the number
         * of segments passed to kexec_load.
         */
        if (nr_segments > KEXEC_SEGMENT_MAX)
                return -EINVAL;

        /* Because we write directly to the reserved memory
         * region when loading crash kernels we need a mutex here to
         * prevent multiple crash  kernels from attempting to load
         * simultaneously, and to prevent a crash kernel from loading
         * over the top of a in use crash kernel.
         *
         * KISS: always take the mutex.
         */
        if (!mutex_trylock(&kexec_mutex))
                return -EBUSY;

        result = do_kexec_load(entry, nr_segments, segments, flags);

        mutex_unlock(&kexec_mutex);

        return result;
}
```



sys_kexec_load()中， 主要干活的是do_kexec_load()

```c
static int do_kexec_load(unsigned long entry, unsigned long nr_segments,
                struct kexec_segment __user *segments, unsigned long flags)
{
        struct kimage **dest_image, *image;
        unsigned long i;
        int ret;

        if (flags & KEXEC_ON_CRASH) {
                dest_image = &kexec_crash_image;
                if (kexec_crash_image)
                        arch_kexec_unprotect_crashkres();
        } else {
                dest_image = &kexec_image;
        }

        if (nr_segments == 0) {
                /* Uninstall image */
                kimage_free(xchg(dest_image, NULL));
                return 0;
        }
        if (flags & KEXEC_ON_CRASH) {
                /*
                 * Loading another kernel to switch to if this one
                 * crashes.  Free any current crash dump kernel before
                 * we corrupt it.
                 */
                kimage_free(xchg(&kexec_crash_image, NULL));
        }

        ret = kimage_alloc_init(&image, entry, nr_segments, segments, flags);
        if (ret)
                return ret;

        if (flags & KEXEC_PRESERVE_CONTEXT)
                image->preserve_context = 1;

        ret = machine_kexec_prepare(image);
        if (ret)
                goto out;

        for (i = 0; i < nr_segments; i++) {
                ret = kimage_load_segment(image, &image->segment[i]);
                if (ret)
                        goto out;
        }

        kimage_terminate(image);

        /* Install the new kernel and uninstall the old */
        image = xchg(dest_image, image);

out:
        if ((flags & KEXEC_ON_CRASH) && kexec_crash_image)
                arch_kexec_protect_crashkres();
                
        kimage_free(image);
        return ret;
}
```



kexec在内核态的信息存储在**kexec_crash_image**, 它是**struct kimage ***类型。

 struct kimage结构体定义如下

```c
struct kimage {
        kimage_entry_t head;
        kimage_entry_t *entry;
        kimage_entry_t *last_entry;

        unsigned long start;
        struct page *control_code_page;
        struct page *swap_page;

        unsigned long nr_segments;
        struct kexec_segment segment[KEXEC_SEGMENT_MAX];

        struct list_head control_pages;
        struct list_head dest_pages;
        struct list_head unusable_pages;

        /* Address of next control page to allocate for crash kernels. */
        unsigned long control_page;

        /* Flags to indicate special processing */
        unsigned int type : 1; 
#define KEXEC_TYPE_DEFAULT 0
#define KEXEC_TYPE_CRASH   1
        unsigned int preserve_context : 1;
        /* If set, we are using file mode kexec syscall */
        unsigned int file_mode:1;
                
#ifdef ARCH_HAS_KIMAGE_ARCH
        struct kimage_arch arch;
#endif

#ifdef CONFIG_KEXEC_FILE
        /* Additional fields for file based kexec syscall */
        void *kernel_buf;
        unsigned long kernel_buf_len;

        void *initrd_buf;
        unsigned long initrd_buf_len;

        char *cmdline_buf;
        unsigned long cmdline_buf_len;

        /* File operations provided by image loader */
        struct kexec_file_ops *fops;

        /* Image loader handling the kernel can store a pointer here */
        void *image_loader_data;

        /* Information for loading purgatory */
        struct purgatory_info purgatory_info;
#endif
};
```

kimage_alloc_init()会分配并初始化struct kimage结构体, 然后在kimage_load_segment()里将用户态准备好的5个segment加载到crash kernel

![kexec_info_segment_02.jpg](http://ww1.sinaimg.cn/large/006CVPwLly1g9dl6dca38j30qo0k00tp.jpg)

kexec_crash_image->start的值为kexec在用户态传入的entry, 即purgatory_start

```c
image->start = entry
```



### kexec相关节点

**/sys/kernel/kexec_loaded**: 快速切换kernel是否打开

```c
static ssize_t kexec_loaded_show(struct kobject *kobj,
                                 struct kobj_attribute *attr, char *buf)
{
        return sprintf(buf, "%d\n", !!kexec_image);
}
KERNEL_ATTR_RO(kexec_loaded);
```



**/sys/kernel/kexec_crash_loaded**: kexec crash是否打开

```c
static ssize_t kexec_crash_loaded_show(struct kobject *kobj,
                                       struct kobj_attribute *attr, char *buf)
{       
        return sprintf(buf, "%d\n", kexec_crash_loaded());
}
KERNEL_ATTR_RO(kexec_crash_loaded);

int kexec_crash_loaded(void)
{
        return !!kexec_crash_image;
}
EXPORT_SYMBOL_GPL(kexec_crash_loaded);
```



**/sys/kernel/kexec_crash_size**: 返回crash kernel大小

```c
static ssize_t kexec_crash_size_show(struct kobject *kobj,
                                       struct kobj_attribute *attr, char *buf)
{       
        return sprintf(buf, "%zu\n", crash_get_memory_size());
}  

size_t crash_get_memory_size(void)
{       
        size_t size = 0;

        mutex_lock(&kexec_mutex);
        if (crashk_res.end != crashk_res.start)
                size = resource_size(&crashk_res);
        mutex_unlock(&kexec_mutex);
        return size;
}
```



**/sys/kernel/vmcoreinfo**: 返回vmcoreinfo_note相关信息

```c
static ssize_t vmcoreinfo_show(struct kobject *kobj,
                               struct kobj_attribute *attr, char *buf)
{
        phys_addr_t vmcore_base = paddr_vmcoreinfo_note();
        return sprintf(buf, "%pa %x\n", &vmcore_base,
                       (unsigned int)sizeof(vmcoreinfo_note));
}       
KERNEL_ATTR_RO(vmcoreinfo);
```



# kdump

## 触发kdump

当kernel panic后， 最终会走到 __crash_kexec

```c
/*
 * No panic_cpu check version of crash_kexec().  This function is called
 * only when panic_cpu holds the current CPU number; this is the only CPU
 * which processes crash_kexec routines.
 */
void __crash_kexec(struct pt_regs *regs)
{
        /* Take the kexec_mutex here to prevent sys_kexec_load
         * running on one cpu from replacing the crash kernel
         * we are using after a panic on a different cpu.
         *
         * If the crash kernel was not located in a fixed area
         * of memory the xchg(&kexec_crash_image) would be
         * sufficient.  But since I reuse the memory...
         */
        if (mutex_trylock(&kexec_mutex)) {
                if (kexec_crash_image) {
                        struct pt_regs fixed_regs;

                        crash_setup_regs(&fixed_regs, regs);
                        crash_save_vmcoreinfo(); 
                        machine_crash_shutdown(&fixed_regs);
                        machine_kexec(kexec_crash_image);
                }
                mutex_unlock(&kexec_mutex);
        }
}
```

crash_setup_regs和machine_crash_shutdown用于保存当前的register信息到vmcore

crash_save_vmcoreinfo用于保存vmcore信息， 如crash time等

最后会进入machine_kexec

```c
/**
 * machine_kexec - Do the kexec reboot.
 *
 * Called from the core kexec code for a sys_reboot with LINUX_REBOOT_CMD_KEXEC.
 */
void machine_kexec(struct kimage *kimage)
{
        phys_addr_t reboot_code_buffer_phys;
        void *reboot_code_buffer;
        bool in_kexec_crash = (kimage == kexec_crash_image);
        bool stuck_cpus = cpus_are_stuck_in_kernel();

        clear_abnormal_magic();

        /*
         * New cpus may have become stuck_in_kernel after we loaded the image.
         */
        BUG_ON(!in_kexec_crash && (stuck_cpus || (num_online_cpus() > 1)));
        WARN(in_kexec_crash && (stuck_cpus || smp_crash_stop_failed()),
                "Some CPUs may be stale, kdump will be unreliable.\n");

        reboot_code_buffer_phys = page_to_phys(kimage->control_code_page);
        reboot_code_buffer = phys_to_virt(reboot_code_buffer_phys);

        kexec_image_info(kimage);

        pr_debug("%s:%d: control_code_page:        %p\n", __func__, __LINE__,
                kimage->control_code_page);
        pr_debug("%s:%d: reboot_code_buffer_phys:  %pa\n", __func__, __LINE__,
                &reboot_code_buffer_phys);
        pr_debug("%s:%d: reboot_code_buffer:       %p\n", __func__, __LINE__,
                reboot_code_buffer);
        pr_debug("%s:%d: relocate_new_kernel:      %p\n", __func__, __LINE__,
                arm64_relocate_new_kernel);
        pr_debug("%s:%d: relocate_new_kernel_size: 0x%lx(%lu) bytes\n",
                __func__, __LINE__, arm64_relocate_new_kernel_size,
                arm64_relocate_new_kernel_size);

        /*
         * Copy arm64_relocate_new_kernel to the reboot_code_buffer for use
         * after the kernel is shut down.
         */
        memcpy(reboot_code_buffer, arm64_relocate_new_kernel,
                arm64_relocate_new_kernel_size);

        /* Flush the reboot_code_buffer in preparation for its execution. */
        __flush_dcache_area(reboot_code_buffer, arm64_relocate_new_kernel_size);
        flush_icache_range((uintptr_t)reboot_code_buffer,
                arm64_relocate_new_kernel_size);

        /* Flush the kimage list and its buffers. */
        kexec_list_flush(kimage);

        /* Flush the new image if already in place. */
        if ((kimage != kexec_crash_image) && (kimage->head & IND_DONE))
                kexec_segment_flush(kimage);

        pr_info("Bye!\n");

        /* Disable all DAIF exceptions. */
        asm volatile ("msr daifset, #0xf" : : : "memory");

        /*
         * cpu_soft_restart will shutdown the MMU, disable data caches, then
         * transfer control to the reboot_code_buffer which contains a copy of
         * the arm64_relocate_new_kernel routine.  arm64_relocate_new_kernel
         * uses physical addressing to relocate the new image to its final
         * position and transfers control to the image entry point when the
         * relocation is complete.
         */

        cpu_soft_restart(kimage != kexec_crash_image,
                reboot_code_buffer_phys, kimage->head, kimage->start, 0);

        BUG(); /* Should never get here. */
}
```

machine_kexec()函数完成的主要功能

- 将arm64_relocate_new_kernel拷贝到kimage的控制代码页中
- 调用cpu_soft_restart, 传入kimage的重要参数

```c
static inline void __noreturn cpu_soft_restart(unsigned long el2_switch,
        unsigned long entry, unsigned long arg0, unsigned long arg1,
        unsigned long arg2)
{
        typeof(__cpu_soft_restart) *restart;

        el2_switch = el2_switch && !is_kernel_in_hyp_mode() &&
                is_hyp_mode_available();
        restart = (void *)virt_to_phys(__cpu_soft_restart);

        cpu_install_idmap();
        restart(el2_switch, entry, arg0, arg1, arg2);
        unreachable();
}
```

继续调用__cpu_soft_restart, 位于arch/arm64/kernel/relocate_kernel.S

```assembly
/*
 * __cpu_soft_restart(el2_switch, entry, arg0, arg1, arg2) - Helper for
 * cpu_soft_restart.
 *
 * @el2_switch: Flag to indicate a swich to EL2 is needed.
 * @entry: Location to jump to for soft reset.
 * arg0: First argument passed to @entry.
 * arg1: Second argument passed to @entry.
 * arg2: Third argument passed to @entry.
 *
 * Put the CPU into the same state as it would be if it had been reset, and
 * branch to what would be the reset vector. It must be executed with the
 * flat identity mapping.
 */
ENTRY(__cpu_soft_restart)
        /* Clear sctlr_el1 flags. */
        mrs     x12, sctlr_el1
        ldr     x13, =SCTLR_ELx_FLAGS
        bic     x12, x12, x13 
        msr     sctlr_el1, x12 
        isb 

        cbz     x0, 1f                          // el2_switch?
        mov     x0, #HVC_SOFT_RESTART
        hvc     #0                              // no return

1:      mov     x18, x1                         // entry
        mov     x0, x2                          // arg0
        mov     x1, x3                          // arg1
        mov     x2, x4                          // arg2
        br      x18 
ENDPROC(__cpu_soft_restart)
```



x18存储是的arm64_relocate_new_kernel,  位于arch/arm64/kernel/relocate_kernel.S

```assembly
/*
 * arm64_relocate_new_kernel - Put a 2nd stage image in place and boot it.
 *
 * The memory that the old kernel occupies may be overwritten when coping the
 * new image to its final location.  To assure that the
 * arm64_relocate_new_kernel routine which does that copy is not overwritten,
 * all code and data needed by arm64_relocate_new_kernel must be between the
 * symbols arm64_relocate_new_kernel and arm64_relocate_new_kernel_end.  The
 * machine_kexec() routine will copy arm64_relocate_new_kernel to the kexec
 * control_code_page, a special page which has been set up to be preserved
 * during the copy operation.
 */
ENTRY(arm64_relocate_new_kernel)

        /* Setup the list loop variables. */
        mov     x17, x1                         /* x17 = kimage_start */
        mov     x16, x0                         /* x16 = kimage_head */
        raw_dcache_line_size x15, x0            /* x15 = dcache line size */
        mov     x14, xzr                        /* x14 = entry ptr */
        mov     x13, xzr                        /* x13 = copy dest */

        /* Clear the sctlr_el2 flags. */
        mrs     x0, CurrentEL
        cmp     x0, #CurrentEL_EL2
        b.ne    1f  
        mrs     x0, sctlr_el2
        ldr     x1, =SCTLR_ELx_FLAGS
        bic     x0, x0, x1
        msr     sctlr_el2, x0
        isb 
1:

        /* Check if the new image needs relocation. */
        tbnz    x16, IND_DONE_BIT, .Ldone

.Lloop:
        and     x12, x16, PAGE_MASK             /* x12 = addr */

        /* Test the entry flags. */
.Ltest_source:
        tbz     x16, IND_SOURCE_BIT, .Ltest_indirection

        /* Invalidate dest page to PoC. */
        mov     x0, x13 
        add     x20, x0, #PAGE_SIZE
        sub     x1, x15, #1
        bic     x0, x0, x1
2:      dc      ivac, x0
        add     x0, x0, x15 
        cmp     x0, x20 
        b.lo    2b  
        dsb     sy 

        mov x20, x13 
        mov x21, x12
        copy_page x20, x21, x0, x1, x2, x3, x4, x5, x6, x7

        /* dest += PAGE_SIZE */
        add     x13, x13, PAGE_SIZE
        b       .Lnext

.Ltest_indirection:
        tbz     x16, IND_INDIRECTION_BIT, .Ltest_destination

        /* ptr = addr */
        mov     x14, x12
        b       .Lnext

.Ltest_destination:
        tbz     x16, IND_DESTINATION_BIT, .Lnext

        /* dest = addr */
        mov     x13, x12

.Lnext:
        /* entry = *ptr++ */
        ldr     x16, [x14], #8

        /* while (!(entry & DONE)) */
        tbz     x16, IND_DONE_BIT, .Lloop

.Ldone:
        /* wait for writes from copy_page to finish */
        dsb     nsh
        ic      iallu
        dsb     nsh
        isb

        /* Start new image. */
        mov     x0, xzr
        mov     x1, xzr
        mov     x2, xzr
        mov     x3, xzr
        br      x17

ENDPROC(arm64_relocate_new_kernel)
```



最后， 会跳转到kimage->start, 也就是kexec用户态的info.entry, 即purgatory_start



purgatory_start位于kexec-tools仓库的purgatory/arch/arm64/entry.S

```assembly
/*
 * ARM64 purgatory.
 */

.macro  size, sym:req
        .size \sym, . - \sym
.endm

.text

.globl purgatory_start
purgatory_start:

        adr     x19, .Lstack
        mov     sp, x19 

        bl      purgatory

        /* Start new image. */
        ldr     x17, arm64_kernel_entry
        ldr     x0, arm64_dtb_addr
        mov     x1, xzr 
        mov     x2, xzr 
        mov     x3, xzr 
        br      x17 

size purgatory_start

.ltorg

.align 4
        .rept   256 
        .quad   0   
        .endr
.Lstack:

.data

.align 3

.globl arm64_kernel_entry
arm64_kernel_entry:
        .quad   0   
size arm64_kernel_entry

.globl arm64_dtb_addr
arm64_dtb_addr:
        .quad   0   
size arm64_dtb_addr

.end
```



purgatory_start主要完成两个功能

- 执行函数purgatory, 完成指定sha256_region的校验
- 跳转到capture kernel entry, 启动新的kernel



## dump vmcore

### elfcorehdr

kernel每次启动时， 都会去检查elfcorehdr是否存在。elfcorehdr主要是为ELF core header预留内存



kernel相关的实现在reserve_elfcorehdr()

```c
static void __init reserve_elfcorehdr(void)
{
        of_scan_flat_dt(early_init_dt_scan_elfcorehdr, NULL);

        if (!elfcorehdr_size)
                return;

        if (memblock_is_region_reserved(elfcorehdr_addr, elfcorehdr_size)) {
                pr_warn("elfcorehdr is overlapped\n");
                return;
        }

        memblock_reserve(elfcorehdr_addr, elfcorehdr_size);

        pr_info("Reserving %lldKB of memory at 0x%llx for elfcorehdr\n",
                elfcorehdr_size >> 10, elfcorehdr_addr);
}
```



其中， early_init_dt_scan_elfcorehdr()是要查找**"linux,elfcorehdr"**的属性. 这个属性是在执行kexec后，设置到capture kernel使用的dtb中。

```c
static int __init early_init_dt_scan_elfcorehdr(unsigned long node,
                const char *uname, int depth, void *data)
{
        const __be32 *reg;
        int len;

        if (depth != 1 || strcmp(uname, "chosen") != 0)
                return 0;

        reg = of_get_flat_dt_prop(node, "linux,elfcorehdr", &len);
        if (!reg || (len < (dt_root_addr_cells + dt_root_size_cells)))
                return 1;

        elfcorehdr_addr = dt_mem_next_cell(dt_root_addr_cells, &reg);
        elfcorehdr_size = dt_mem_next_cell(dt_root_size_cells, &reg);

        return 1;
}
```

ELF core header信息会存储到**elfcorehdr_addr**/**elfcorehdr_size**



### vmcore_init

vmcore_init实现如下

```c
/* Init function for vmcore module. */
static int __init vmcore_init(void)
{
        int rc = 0; 

        /* Allow architectures to allocate ELF header in 2nd kernel */
        rc = elfcorehdr_alloc(&elfcorehdr_addr, &elfcorehdr_size);
        if (rc) 
                return rc;
        /*
         * If elfcorehdr= has been passed in cmdline or created in 2nd kernel,
         * then capture the dump.
         */
        if (!(is_vmcore_usable()))
                return rc;
        rc = parse_crash_elf_headers();
        if (rc) {
                pr_warn("Kdump: vmcore not initialized\n");
                return rc;
        }
        elfcorehdr_free(elfcorehdr_addr);
        elfcorehdr_addr = ELFCORE_ADDR_ERR;

        proc_vmcore = proc_create("vmcore", S_IRUSR, NULL, &proc_vmcore_operations);
        if (proc_vmcore)
                proc_vmcore->size = vmcore_size;
        return 0;
}
fs_initcall(vmcore_init);
```



vmcore_init主要实现了以下功能

- is_vmcore_usable() 检查ELF core header是否存在，来决定vmcore是否可用

- parse_crash_elf_headers()用于解析ELF core header
- proc_create用于创建/proc/vmcore结点



#### is_vmcore_usable

```c
/*
 * is_kdump_kernel() checks whether this kernel is booting after a panic of
 * previous kernel or not. This is determined by checking if previous kernel
 * has passed the elf core header address on command line.
 *
 * This is not just a test if CONFIG_CRASH_DUMP is enabled or not. It will
 * return 1 if CONFIG_CRASH_DUMP=y and if kernel is booting after a panic of
 * previous kernel.
 */

static inline int is_kdump_kernel(void)
{
        return (elfcorehdr_addr != ELFCORE_ADDR_MAX) ? 1 : 0;
}

/* is_vmcore_usable() checks if the kernel is booting after a panic and
 * the vmcore region is usable.
 *
 * This makes use of the fact that due to alignment -2ULL is not
 * a valid pointer, much in the vain of IS_ERR(), except
 * dealing directly with an unsigned long long rather than a pointer.
 */

static inline int is_vmcore_usable(void)
{
        return is_kdump_kernel() && elfcorehdr_addr != ELFCORE_ADDR_ERR ? 1 : 0;
}
```



#### parse_crash_elf_headers

- 将PT_NOTE的program header合并成一个，数据存放到**elfnotes_buf**
- 将PT_LOAD的promgram header信息存放到**vmcore_list**

vmcore_list是个双向链表， 每个结点是struct vmcore，定义如下

```
struct vmcore {
        struct list_head list;
        unsigned long long paddr;
        unsigned long long size;
        loff_t offset;
};
```



vmcore header结构如下

![vmcore_01.jpg](http://ww1.sinaimg.cn/large/006CVPwLly1g9eqc3m581j30qo0k00t5.jpg)

#### proc_create

```c
static inline struct proc_dir_entry *proc_create(
        const char *name, umode_t mode, struct proc_dir_entry *parent,
        const struct file_operations *proc_fops)
{
        return proc_create_data(name, mode, parent, proc_fops, NULL);
}

struct proc_dir_entry *proc_create_data(const char *name, umode_t mode,
                                        struct proc_dir_entry *parent,
                                        const struct file_operations *proc_fops,
                                        void *data)
{
        struct proc_dir_entry *pde;
        if ((mode & S_IFMT) == 0)
                mode |= S_IFREG;

        if (!S_ISREG(mode)) {
                WARN_ON(1);     /* use proc_mkdir() */
                return NULL;
        }

        BUG_ON(proc_fops == NULL);

        if ((mode & S_IALLUGO) == 0)
                mode |= S_IRUGO;
        pde = __proc_create(&parent, name, mode, 1);
        if (!pde)
                goto out;
        pde->proc_fops = proc_fops;
        pde->data = data;
        pde->proc_iops = &proc_file_inode_operations;
        if (proc_register(parent, pde) < 0)
                goto out_free;
        return pde;
out_free:
        kfree(pde);
out:
        return NULL;
}
```



/proc/vmcore结点被创建后， 

```c
static const struct file_operations proc_vmcore_operations = {
        .read           = read_vmcore,
        .llseek         = default_llseek,
        .mmap           = mmap_vmcore,
};
```



当读取该结点时， 会调用到read_vmcore()->__read_vmcore()

```c
/* Read from the ELF header and then the crash dump. On error, negative value is
 * returned otherwise number of bytes read are returned.
 */
static ssize_t __read_vmcore(char *buffer, size_t buflen, loff_t *fpos,
                             int userbuf)
{
        ssize_t acc = 0, tmp;
        size_t tsz;
        u64 start;
        struct vmcore *m = NULL;

        if (buflen == 0 || *fpos >= vmcore_size)
                return 0;

        /* trim buflen to not go beyond EOF */
        if (buflen > vmcore_size - *fpos)
                buflen = vmcore_size - *fpos;

        /* Read ELF core header */
        if (*fpos < elfcorebuf_sz) {
                tsz = min(elfcorebuf_sz - (size_t)*fpos, buflen);
                if (copy_to(buffer, elfcorebuf + *fpos, tsz, userbuf))
                        return -EFAULT;
                buflen -= tsz;
                *fpos += tsz;
                buffer += tsz;
                acc += tsz;

                /* leave now if filled buffer already */
                if (buflen == 0)
                        return acc;
        }

        /* Read Elf note segment */
        if (*fpos < elfcorebuf_sz + elfnotes_sz) {
                void *kaddr;

                tsz = min(elfcorebuf_sz + elfnotes_sz - (size_t)*fpos, buflen);
                kaddr = elfnotes_buf + *fpos - elfcorebuf_sz;
                if (copy_to(buffer, kaddr, tsz, userbuf))
                        return -EFAULT;
                buflen -= tsz;
                *fpos += tsz;
                buffer += tsz;
                acc += tsz;

                /* leave now if filled buffer already */
                if (buflen == 0)
                        return acc;
        }

        list_for_each_entry(m, &vmcore_list, list) {
                if (*fpos < m->offset + m->size) {
                        tsz = (size_t)min_t(unsigned long long,
                                            m->offset + m->size - *fpos,
                                            buflen);
                        start = m->paddr + *fpos - m->offset;
                        tmp = read_from_oldmem(buffer, tsz, &start, userbuf);
                        if (tmp < 0)
                                return tmp;
                        buflen -= tsz;
                        *fpos += tsz;
                        buffer += tsz;
                        acc += tsz;

                        /* leave now if filled buffer already */
                        if (buflen == 0)
                                return acc;
                }
        }

        return acc;
}
```



该函数会依次读取ELF header, elfnotes_buf和vmcore_list, 从而生成完整的vmcore文件。

![vmcore_02.jpg](http://ww1.sinaimg.cn/large/006CVPwLly1g9eqcpu0r1j30qo0k0my3.jpg)

### 导出vmcore

新的kernel启动后， 我们可以直接导出/proc/vmcore,  如在挂载文件系统后， 将/proc/vmcore压缩到本地硬盘。

```shell
$ tar -czf /mnt/vmcore.tar.gz /proc/vmcore
```





## 分析vmcore

/proc/vmcore导出后， 通常借助crash工具进行离线分析。



```shell
$ crash vmlinux proc/vmcore 

crash 7.2.5
Copyright (C) 2002-2019  Red Hat, Inc.
Copyright (C) 2004, 2005, 2006, 2010  IBM Corporation
Copyright (C) 1999-2006  Hewlett-Packard Co
Copyright (C) 2005, 2006, 2011, 2012  Fujitsu Limited
Copyright (C) 2006, 2007  VA Linux Systems Japan K.K.
Copyright (C) 2005, 2011  NEC Corporation
Copyright (C) 1999, 2002, 2007  Silicon Graphics, Inc.
Copyright (C) 1999, 2000, 2001, 2002  Mission Critical Linux, Inc.
This program is free software, covered by the GNU General Public License,
and you are welcome to change it and/or distribute copies of it under
certain conditions.  Enter "help copying" to see the conditions.
This program has absolutely no warranty.  Enter "help warranty" for details.
 
GNU gdb (GDB) 7.6
Copyright (C) 2013 Free Software Foundation, Inc.
License GPLv3+: GNU GPL version 3 or later <http://gnu.org/licenses/gpl.html>
This is free software: you are free to change and redistribute it.
There is NO WARRANTY, to the extent permitted by law.  Type "show copying"
and "show warranty" for details.
This GDB was configured as "--host=x86_64-unknown-linux-gnu --target=aarch64-elf-linux"...
Redefine command "pstring"? (y or n) [answered Y; input not from terminal]

      KERNEL: vmlinux                           
    DUMPFILE: proc/vmcore
        CPUS: 8
        DATE: Mon Oct 28 21:44:54 2019
      UPTIME: 00:29:23
LOAD AVERAGE: 0.00, 0.00, 0.00
       TASKS: 176
    NODENAME: chiptim
     RELEASE: 4.9.38-chip_v1.0.0-00253-gece0e28-dirty
     VERSION: #1 SMP Thu Aug 22 21:27:26 HKT 2019
     MACHINE: aarch64  (unknown Mhz)
      MEMORY: 15.8 GB
       PANIC: "sysrq: SysRq : Trigger a crash"
         PID: 978
     COMMAND: "bash"
        TASK: ffffffc2ea91bc00  [THREAD_INFO: ffffffc2ea91bc00]
         CPU: 0
       STATE: TASK_RUNNING (SYSRQ)

crash> bt
PID: 978    TASK: ffffffc2ea91bc00  CPU: 0   COMMAND: "bash"
 #0 [ffffffc2e5253880] machine_kexec at ffffff80080940e0
 #1 [ffffffc2e52538e0] __crash_kexec at ffffff800811d430
 #2 [ffffffc2e5253a30] __crash_kexec at ffffff800811d4e8
 #3 [ffffffc2e5253a50] crash_kexec at ffffff800811d558
 #4 [ffffffc2e5253a70] die at ffffff8008088db4
 #5 [ffffffc2e5253ab0] __do_kernel_fault at ffffff8008099c64
 #6 [ffffffc2e5253ae0] do_page_fault at ffffff8008097560
 #7 [ffffffc2e5253b50] do_translation_fault at ffffff8008097668
 #8 [ffffffc2e5253b60] do_mem_abort at ffffff8008081294
 #9 [ffffffc2e5253d40] el1_ia at ffffff800808260c
     PC: ffffff80084915ac  [sysrq_handle_crash+20]
     LR: ffffff800849202c  [__handle_sysrq+284]
     SP: ffffffc2e5253d40  PSTATE: 00000145
    X29: ffffffc2e5253d40  X28: ffffffc2ea91bc00  X27: ffffff8008852000
    X26: 0000000000000040  X25: 0000000000000123  X24: 0000000000000015
    X23: 0000000000000000  X22: 0000000000000007  X21: ffffff8008bb0da8
    X20: 0000000000000063  X19: ffffff8008b6c000  X18: 0000000000000000
    X17: 0000007f9d45b120  X16: ffffff80081d5700  X15: ffffffffffffffff
    X14: 0000000000000000  X13: 0000000000000007  X12: 0000000000000161
    X11: 0000000000000006  X10: 0000000000000161   X9: 0000000000000001
     X8: ffffff800839a988   X7: 0000000000000008   X6: ffffff8008db3c08
     X5: 0000000000000000   X4: 0000000000000000   X3: 0000000000000000
     X2: ffffffc2ffb0e700   X1: 0000000000000000   X0: 0000000000000001
#10 [ffffffc2e5253d80] write_sysrq_trigger at ffffff8008492494
#11 [ffffffc2e5253da0] proc_reg_write at ffffff8008234090
#12 [ffffffc2e5253dc0] __vfs_write at ffffff80081d3758
#13 [ffffffc2e5253e40] vfs_write at ffffff80081d4518
#14 [ffffffc2e5253e80] sys_write at ffffff80081d5740
#15 [ffffffc2e5253ec0] el0_svc_naked at ffffff8008082f2c
     PC: 0000007f9d4af078   LR: 0000007f9d45e2f8   SP: 0000007fdabec300
    X29: 0000007fdabec300  X28: 0000007fdabec484  X27: 0000000000000000
    X26: 0000000000000000  X25: 0000000000000000  X24: 0000000000000002
    X23: 0000007f9d534638  X22: 0000000000000002  X21: 0000007f9d538480
    X20: 0000000000516808  X19: 0000000000000002  X18: 0000000000000000
    X17: 0000007f9d45b120  X16: 0000000000000000  X15: 0000000000000000
    X14: 0000000000000000  X13: 0000000000000000  X12: 0000000000000000
    X11: 0000000000000020  X10: 0000000000000000   X9: 0000000000000000
     X8: 0000000000000040   X7: 0000000000000001   X6: 0000000000000063
     X5: 5551000454000000   X4: 0000000000000888   X3: 0000000000000000
     X2: 0000000000000002   X1: 0000000000516808   X0: 0000000000000001
    ORIG_X0: 0000000000000001  SYSCALLNO: 40  PSTATE: 20000000
```

​          

---



![programmer8.jpg](http://ww1.sinaimg.cn/large/005Kyrj9ly1gbvsonijdoj3076076wex.jpg)

<center>
程序员自我修养(ID: dumphex)
</center>

---
