---
title: C++中的局部静态对象
date: 2020-03-09 10:49:18
tags:
- local static object
- __cxa_guard_acquire
- __cxa_guard_release
- __run_exit_handlers
categories: C/C++
---

本文分析了局部静态对象的构造和析构过程。

<!-- more -->

# 1. 测试环境
- Linux ubuntu18arm64 4.15.0-76-generic #86-Ubuntu SMP Fri Jan 17 17:25:58 UTC 2020 aarch64 aarch64 aarch64 GNU/Linux
- gcc version 7.4.0 (Ubuntu/Linaro 7.4.0-1ubuntu1~18.04.1)
- glibc 2.27
- c++11


# 2. 调试分析
局部静态对象， 就是在函数内定义的静态对象。
只有当函数第一次调用时，该对象才执行初始化，否则保持当前状态，后续不再初始化。

## 2.1 测试源码
```cpp
#include <iostream>

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

void local_static() {
  static Base local_static_obj(3);
}
```


local_static()反汇编如下:

```asm
(gdb) disas
Dump of assembler code for function local_static():
   0x0000aaaaaaaaaf34 <+0>:	stp	x29, x30, [sp, #-16]!
   0x0000aaaaaaaaaf38 <+4>:	mov	x29, sp
=> 0x0000aaaaaaaaaf3c <+8>:	adrp	x0, 0xaaaaaaabc000
   0x0000aaaaaaaaaf40 <+12>:	add	x0, x0, #0x30
   0x0000aaaaaaaaaf44 <+16>:	ldarb	w0, [x0]
   0x0000aaaaaaaaaf48 <+20>:	and	w0, w0, #0xff
   0x0000aaaaaaaaaf4c <+24>:	and	w0, w0, #0x1
   0x0000aaaaaaaaaf50 <+28>:	cmp	w0, #0x0
   0x0000aaaaaaaaaf54 <+32>:	cset	w0, eq  // eq = none
   0x0000aaaaaaaaaf58 <+36>:	and	w0, w0, #0xff
   0x0000aaaaaaaaaf5c <+40>:	cmp	w0, #0x0
   0x0000aaaaaaaaaf60 <+44>:	b.eq	0xaaaaaaaaafbc <local_static()+136>  // b.none
   0x0000aaaaaaaaaf64 <+48>:	adrp	x0, 0xaaaaaaabc000
   0x0000aaaaaaaaaf68 <+52>:	add	x0, x0, #0x30
   0x0000aaaaaaaaaf6c <+56>:	bl	0xaaaaaaaaad60 <__cxa_guard_acquire@plt>
   0x0000aaaaaaaaaf70 <+60>:	cmp	w0, #0x0
   0x0000aaaaaaaaaf74 <+64>:	cset	w0, ne  // ne = any
   0x0000aaaaaaaaaf78 <+68>:	and	w0, w0, #0xff
   0x0000aaaaaaaaaf7c <+72>:	cmp	w0, #0x0
   0x0000aaaaaaaaaf80 <+76>:	b.eq	0xaaaaaaaaafbc <local_static()+136>  // b.none
   0x0000aaaaaaaaaf84 <+80>:	adrp	x0, 0xaaaaaaabc000
   0x0000aaaaaaaaaf88 <+84>:	add	x0, x0, #0x28
   0x0000aaaaaaaaaf8c <+88>:	mov	w1, #0x3                   	// #3
   0x0000aaaaaaaaaf90 <+92>:	bl	0xaaaaaaaab098 <Base::Base(int)>
   0x0000aaaaaaaaaf94 <+96>:	adrp	x0, 0xaaaaaaabc000
   0x0000aaaaaaaaaf98 <+100>:	add	x0, x0, #0x30
   0x0000aaaaaaaaaf9c <+104>:	bl	0xaaaaaaaaacf0 <__cxa_guard_release@plt>
   0x0000aaaaaaaaafa0 <+108>:	adrp	x0, 0xaaaaaaabc000
   0x0000aaaaaaaaafa4 <+112>:	add	x2, x0, #0x8
   0x0000aaaaaaaaafa8 <+116>:	adrp	x0, 0xaaaaaaabc000
   0x0000aaaaaaaaafac <+120>:	add	x1, x0, #0x28
   0x0000aaaaaaaaafb0 <+124>:	adrp	x0, 0xaaaaaaaab000 <__static_initialization_and_destruction_0(int, int)+16>
   0x0000aaaaaaaaafb4 <+128>:	add	x0, x0, #0xbc
   0x0000aaaaaaaaafb8 <+132>:	bl	0xaaaaaaaaad30 <__cxa_atexit@plt>
   0x0000aaaaaaaaafbc <+136>:	nop
   0x0000aaaaaaaaafc0 <+140>:	ldp	x29, x30, [sp], #16
   0x0000aaaaaaaaafc4 <+144>:	ret
End of assembler dump.
```

## 2.2 构造
局部静态对象的构造大概分为以下几步

- 判断guard variable
- 调用__cxa_guard_acquire()
- 调用构造函数
- 调用__cxa_guard_release()
- 注册析构函数

### 2.2.1 判断guard variable
每个局部静态对象，编译器为其生成**guard variable**，用于标识对应的局部静态对象是否已初始化并确保线程安全
```shell
$ nm out/bin/objects | grep local_static
0000000000000f34 T _Z12local_staticv
0000000000012030 b _ZGVZ12local_staticvE16local_static_obj
0000000000012028 b _ZZ12local_staticvE16local_static_obj

$ c++filt _ZGVZ12local_staticvE16local_static_obj
guard variable for local_static()::local_static_obj

$ c++filt _ZZ12local_staticvE16local_static_obj
local_static()::local_static_obj
```

假设guard variable为gv, int *pgv = &gv, 

gv的三个flag含义如下: 
- pgv[0]为**guard bit**, 标识是否**完成初始化**
- pgv[1]为**pending bit**，标识是否**正在初始**化
- pgv[2]为**waiting bit**，标识是否**等待初始化**


在本例中，guard variable位于0xaaaaaaabc000 + 0x30 = 0xaaaaaaabc030
```asm
=> 0x0000aaaaaaaaaf3c <+8>:	adrp	x0, 0xaaaaaaabc000
   0x0000aaaaaaaaaf40 <+12>:	add	x0, x0, #0x30
   0x0000aaaaaaaaaf44 <+16>:	ldarb	w0, [x0]
   0x0000aaaaaaaaaf48 <+20>:	and	w0, w0, #0xff
   0x0000aaaaaaaaaf4c <+24>:	and	w0, w0, #0x1
   0x0000aaaaaaaaaf50 <+28>:	cmp	w0, #0x0
   0x0000aaaaaaaaaf54 <+32>:	cset	w0, eq  // eq = none
   0x0000aaaaaaaaaf58 <+36>:	and	w0, w0, #0xff
   0x0000aaaaaaaaaf5c <+40>:	cmp	w0, #0x0
   0x0000aaaaaaaaaf60 <+44>:	b.eq	0xaaaaaaaaafbc <local_static()+136>  // b.none
```

- 若局部静态对象未初始化或正在初始化，则第1次load的w0为0x00, 判断为0后再设置为1, 表示要继续往下执行__cxa_guard_acquire()

- 若局部静态对象已完成初始化，则load的w0为1，判断为非0后再设置为0, 则不再执行__cxa_guard_acquire()和调用构造函数，直接执行局部静态对象后面的代码(0xaaaaaaaaafbc)。


### 2.2.2 __cxa_guard_acquire()
> 源文件: gcc/libstdc++-v3/libsupc++/guard.cc

关键代码如下
```cpp
    if (__gthread_active_p ())
      {
        int *gi = (int *) (void *) g;
        const int guard_bit = _GLIBCXX_GUARD_BIT;
        const int pending_bit = _GLIBCXX_GUARD_PENDING_BIT;
        const int waiting_bit = _GLIBCXX_GUARD_WAITING_BIT;
        
        while (1)
          {
            int expected(0);
            if (__atomic_compare_exchange_n(gi, &expected, pending_bit, false,
                                            __ATOMIC_ACQ_REL,
                                            __ATOMIC_ACQUIRE))
              {
                // This thread should do the initialization.
                return 1;
              }
               
            if (expected == guard_bit)
              { 
                // Already initialized.
                return 0;
              }
    
             if (expected == pending_bit)
               { 
                 // Use acquire here.
                 int newv = expected | waiting_bit;
                 if (!__atomic_compare_exchange_n(gi, &expected, newv, false,
                                                  __ATOMIC_ACQ_REL, 
                                                  __ATOMIC_ACQUIRE))
                   {
                     if (expected == guard_bit)
                       {
                         // Make a thread that failed to set the
                         // waiting bit exit the function earlier,
                         // if it detects that another thread has
                         // successfully finished initialising.
                         return 0;
                       }
                     if (expected == 0)
                       continue;
                   }
                 
                 expected = newv;
               }
            
            syscall (SYS_futex, gi, _GLIBCXX_FUTEX_WAIT, expected, 0);
          }
      }
```

- 若局部静态对象未初始化过， 则这三个标志均为0x00
  ```asm
  (gdb) x/1xg 0xaaaaaaabc030
  0xaaaaaaabc030 <_ZGVZ12local_staticvE16local_static_obj>:	0x0000000000000000
  ```

- 若第1个线程刚进来，则设置**pending bit**, 标识局部静态对象**正在初始化**
  ```asm
  (gdb) x/1xg 0xaaaaaaabc030
  0xaaaaaaabc030 <_ZGVZ12local_staticvE16local_static_obj>:	0x0000000000000100
  ```

- 若第1个线程未完成，第2个线程又进来尝试初始化，则设置**waiting bit**, 并调用futex系统调用进入休眠状态(当第1个线程完成初始化后，会再唤醒正在休眠的线程)


### 2.2.3 调用构造函数

第1个线程从__cxa_guard_acquire()返回1后，下一步调用构造函数进行初始化
```asm
   0x0000aaaaaaaaaf84 <+80>:	adrp	x0, 0xaaaaaaabc000
   0x0000aaaaaaaaaf88 <+84>:	add	x0, x0, #0x28
   0x0000aaaaaaaaaf8c <+88>:	mov	w1, #0x3                   	// #3
   0x0000aaaaaaaaaf90 <+92>:	bl	0xaaaaaaaab098 <Base::Base(int)>
```

传给构造函数的参数如下
- 第1个参数是局部静态对象的地址x0 = 0xaaaaaaabc028
- 第2个参数是w1 = 3

### 2.2.4 __cxa_guard_release()
> 源文件: gcc/libstdc++-v3/libsupc++/guard.cc

__cxa_guard_release()的实现如下:
```cpp
  extern "C" 
  void __cxa_guard_release (__guard *g) throw ()
  {
#ifdef _GLIBCXX_USE_FUTEX
    // If __atomic_* and futex syscall are supported, don't use any global
    // mutex.
    if (__gthread_active_p ()) 
      {   
        int *gi = (int *) (void *) g;
        const int guard_bit = _GLIBCXX_GUARD_BIT;
        const int waiting_bit = _GLIBCXX_GUARD_WAITING_BIT;
        int old = __atomic_exchange_n (gi, guard_bit, __ATOMIC_ACQ_REL);

        if ((old & waiting_bit) != 0)
          syscall (SYS_futex, gi, _GLIBCXX_FUTEX_WAKE, INT_MAX);
        return;
      }   
#elif defined(__GTHREAD_HAS_COND)
    if (__gthread_active_p())
      {   
        mutex_wrapper mw; 

        set_init_in_progress_flag(g, 0); 
        _GLIBCXX_GUARD_SET_AND_RELEASE(g);

        get_static_cond().broadcast();
        return;
      }   
#endif

    set_init_in_progress_flag(g, 0); 
    _GLIBCXX_GUARD_SET_AND_RELEASE (g);

#if defined(__GTHREADS) && !defined(__GTHREAD_HAS_COND)
    // This provides compatibility with older systems not supporting POSIX like
    // condition variables.
    if (__gthread_active_p())
      static_mutex->unlock();
#endif
  }
}
```

该函数完成的主要功能如下
- 设置guard variable
  ```asm
  (gdb) x/1xg 0xaaaaaaabc030
  0xaaaaaaabc030 <_ZGVZ12local_staticvE16local_static_obj>:	0x0000000000000001
  ```

  这里只设置了guard bit, pending bit和waiting bit已清除， 标识局部静态对象已完成初始化。

- 若waiting_bit已设置，则调用futex()唤醒正在休眠的线程。休眠线程醒来，会再次检查: 若guard bit已设置，则返回0，不必再执行初始化。

### 2.2.5 注册析构函数

在local_static()函数的最后， 
```asm
   0x0000aaaaaaaaafa0 <+108>:	adrp	x0, 0xaaaaaaabc000
   0x0000aaaaaaaaafa4 <+112>:	add	x2, x0, #0x8
   0x0000aaaaaaaaafa8 <+116>:	adrp	x0, 0xaaaaaaabc000
   0x0000aaaaaaaaafac <+120>:	add	x1, x0, #0x28
   0x0000aaaaaaaaafb0 <+124>:	adrp	x0, 0xaaaaaaaab000 <__static_initialization_and_destruction_0(int, int)+16>
   0x0000aaaaaaaaafb4 <+128>:	add	x0, x0, #0xbc
   0x0000aaaaaaaaafb8 <+132>:	bl	0xaaaaaaaaad30 <__cxa_atexit@plt>
```

这里调用__cxa_atexit()注册局部静态对象的析构函数
- 第1个参数x0 = 0x0000aaaaaaaab0bc是Base::~Base()
- 第2个参数x1 = 0xaaaaaaabc028是局部静态对象的地址
- 第3个参数x2 = 0xaaaaaaabc008是dso handler


__cxa_atexit()的实现如下
> 源文件: glibc/stdlib/cxa_atexit.c

```c
int
attribute_hidden
__internal_atexit (void (*func) (void *), void *arg, void *d, 
                   struct exit_function_list **listp)
{
  struct exit_function *new;

  __libc_lock_lock (__exit_funcs_lock);
  new = __new_exitfn (listp);

  if (new == NULL)
    {   
      __libc_lock_unlock (__exit_funcs_lock);
      return -1; 
    }   

#ifdef PTR_MANGLE
  PTR_MANGLE (func);
#endif
  new->func.cxa.fn = (void (*) (void *, int)) func;
  new->func.cxa.arg = arg;
  new->func.cxa.dso_handle = d;
  new->flavor = ef_cxa;
  __libc_lock_unlock (__exit_funcs_lock);
  return 0;
}


/* Register a function to be called by exit or when a shared library
   is unloaded.  This function is only called from code generated by
   the C++ compiler.  */
int
__cxa_atexit (void (*func) (void *), void *arg, void *d) 
{
  return __internal_atexit (func, arg, d, &__exit_funcs);
}
libc_hidden_def (__cxa_atexit)
```

__exit_funcs是个结构体指针， 指向initial， 以链表形式存放
```c
static struct exit_function_list initial;
struct exit_function_list *__exit_funcs = &initial;
```

## 2.3 析构

局部静态对象析构时的堆栈如下:
```asm
(gdb) bt
#0  Base::~Base (this=0xaaaaaaabc028 <local_static()::local_static_obj>, __in_chrg=<optimized out>) at /home/timzhang/project/github/dumphex/cppTestSuite/src/objects.cc:9
#1  0x0000fffff7d19e34 in __run_exit_handlers (status=0, listp=0xfffff7e385a0 <__exit_funcs>, run_list_atexit=255, run_list_atexit@entry=true, run_dtors=run_dtors@entry=true) at exit.c:108
#2  0x0000fffff7d19f6c in __GI_exit (status=<optimized out>) at exit.c:139
#3  0x0000fffff7d056e4 in __libc_start_main (main=0x0, argc=0, argv=0x0, init=<optimized out>, fini=<optimized out>, rtld_fini=<optimized out>, stack_end=<optimized out>) at ../csu/libc-start.c:344
#4  0x0000aaaaaaaaadb4 in _start ()
Backtrace stopped: previous frame identical to this frame (corrupt stack?)
```


exit()的实现如下
> 源文件: glibc/stdlib/exit.c

```c
/* Call all functions registered with `atexit' and `on_exit',
   in the reverse of the order in which they were registered
   perform stdio cleanup, and terminate program execution with STATUS.  */
void
attribute_hidden
__run_exit_handlers (int status, struct exit_function_list **listp,
		     bool run_list_atexit, bool run_dtors)
{
  /* First, call the TLS destructors.  */
#ifndef SHARED
  if (&__call_tls_dtors != NULL)
#endif
    if (run_dtors)
      __call_tls_dtors ();

  /* We do it this way to handle recursive calls to exit () made by
     the functions registered with `atexit' and `on_exit'. We call
     everyone on the list and use the status value in the last
     exit (). */
  while (true)
    {
      struct exit_function_list *cur;

      __libc_lock_lock (__exit_funcs_lock);

    restart:
      cur = *listp;

      if (cur == NULL)
	{
	  /* Exit processing complete.  We will not allow any more
	     atexit/on_exit registrations.  */
	  __exit_funcs_done = true;
	  __libc_lock_unlock (__exit_funcs_lock);
	  break;
	}

      while (cur->idx > 0)
	{
	  struct exit_function *const f = &cur->fns[--cur->idx];
	  const uint64_t new_exitfn_called = __new_exitfn_called;

	  /* Unlock the list while we call a foreign function.  */
	  __libc_lock_unlock (__exit_funcs_lock);
	  switch (f->flavor)
	    {
	      void (*atfct) (void);
	      void (*onfct) (int status, void *arg);
	      void (*cxafct) (void *arg, int status);

	    case ef_free:
	    case ef_us:
	      break;
	    case ef_on:
	      onfct = f->func.on.fn;
#ifdef PTR_DEMANGLE
	      PTR_DEMANGLE (onfct);
#endif
	      onfct (status, f->func.on.arg);
	      break;
	    case ef_at:
	      atfct = f->func.at;
#ifdef PTR_DEMANGLE
	      PTR_DEMANGLE (atfct);
#endif
	      atfct ();
	      break;
	    case ef_cxa:
	      /* To avoid dlclose/exit race calling cxafct twice (BZ 22180),
		 we must mark this function as ef_free.  */
	      f->flavor = ef_free;
	      cxafct = f->func.cxa.fn;
#ifdef PTR_DEMANGLE
	      PTR_DEMANGLE (cxafct);
#endif
	      cxafct (f->func.cxa.arg, status);
	      break;
	    }
	  /* Re-lock again before looking at global state.  */
	  __libc_lock_lock (__exit_funcs_lock);

	  if (__glibc_unlikely (new_exitfn_called != __new_exitfn_called))
	    /* The last exit function, or another thread, has registered
	       more exit functions.  Start the loop over.  */
	    goto restart;
	}

      *listp = cur->next;
      if (*listp != NULL)
	/* Don't free the last element in the chain, this is the statically
	   allocate element.  */
	free (cur);

      __libc_lock_unlock (__exit_funcs_lock);
    }

  if (run_list_atexit)
    RUN_HOOK (__libc_atexit, ());

  _exit (status);
}


void
exit (int status)
{
  __run_exit_handlers (status, &__exit_funcs, true, true);
}
libc_hidden_def (exit)
```

可以看到， 程序在退出前，调用exit()->__run_exit_handlers(), 传入中的是__exit_funcs, 正是之前注册析构函数的地方。

# 3. 总结
- 局部静态对象在函数第一次调用时完成初始化，这在C++11后是**线程安全**的。同时注册了析构函数。
- 局部静态对象拥有和程序同样的生命周期，在程序exit时会调用之前注册的析构函数。

---

![程序员自我修养](http://ww1.sinaimg.cn/large/005Kyrj9ly1gbvsonijdoj3076076wex.jpg)

<center>
程序员自我修养(ID: dumphex)
</center>

---
