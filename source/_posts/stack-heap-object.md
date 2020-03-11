---
title: C++中的栈对象与堆对象
date: 2020-03-04 15:08:06
tags:
- stack object
- heap object
- new
- delete
categories: C/C++
---

本文分析了栈对象和堆对象的构造和析构过程。

<!-- more -->

# 1. 测试环境
- Linux ubuntu18arm64 4.15.0-76-generic #86-Ubuntu SMP Fri Jan 17 17:25:58 UTC 2020 aarch64 aarch64 aarch64 GNU/Linux
- gcc version 7.4.0 (Ubuntu/Linaro 7.4.0-1ubuntu1~18.04.1)
- c++11

# 2. 调试分析
在本文的栈对象和堆对象示例中，我们统一使用如下class。
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
```

## 2.1 栈对象
### 2.1.1 测试代码
```cpp
void stack() {
  Base stack_obj(1);
}
```

stack()的反汇编如下
```asm
(gdb) disas
Dump of assembler code for function stack():
   0x0000aaaaaaaaae84 <+0>:	stp	x29, x30, [sp, #-32]!
   0x0000aaaaaaaaae88 <+4>:	mov	x29, sp
   0x0000aaaaaaaaae8c <+8>:	adrp	x0, 0xaaaaaaabb000
   0x0000aaaaaaaaae90 <+12>:	ldr	x0, [x0, #4024]
   0x0000aaaaaaaaae94 <+16>:	ldr	x1, [x0]
   0x0000aaaaaaaaae98 <+20>:	str	x1, [x29, #24]
   0x0000aaaaaaaaae9c <+24>:	mov	x1, #0x0                   	// #0
   0x0000aaaaaaaaaea0 <+28>:	add	x0, x29, #0x10
   0x0000aaaaaaaaaea4 <+32>:	mov	w1, #0x1                   	// #1
   0x0000aaaaaaaaaea8 <+36>:	bl	0xaaaaaaaab098 <Base::Base(int)>
=> 0x0000aaaaaaaaaeac <+40>:	add	x0, x29, #0x10
   0x0000aaaaaaaaaeb0 <+44>:	bl	0xaaaaaaaab0bc <Base::~Base()>
   0x0000aaaaaaaaaeb4 <+48>:	nop
   0x0000aaaaaaaaaeb8 <+52>:	adrp	x0, 0xaaaaaaabb000
   0x0000aaaaaaaaaebc <+56>:	ldr	x0, [x0, #4024]
   0x0000aaaaaaaaaec0 <+60>:	ldr	x1, [x29, #24]
   0x0000aaaaaaaaaec4 <+64>:	ldr	x0, [x0]
   0x0000aaaaaaaaaec8 <+68>:	eor	x0, x1, x0
   0x0000aaaaaaaaaecc <+72>:	cmp	x0, #0x0
   0x0000aaaaaaaaaed0 <+76>:	b.eq	0xaaaaaaaaaed8 <stack()+84>  // b.none
   0x0000aaaaaaaaaed4 <+80>:	bl	0xaaaaaaaaacd0 <__stack_chk_fail@plt>
   0x0000aaaaaaaaaed8 <+84>:	ldp	x29, x30, [sp], #32
   0x0000aaaaaaaaaedc <+88>:	ret
End of assembler dump.
```

### 2.1.2 构造
```asm
   0x0000aaaaaaaaadc0 <+28>:	add	x0, x29, #0x10
   0x0000aaaaaaaaadc4 <+32>:	mov	w1, #0x1                   	// #1
   0x0000aaaaaaaaadc8 <+36>:	bl	0xaaaaaaaab008 <Base::Base(int)>
```
在本例里，**栈对象的地址是x29 + 0x10**, x29就是fp, 用于标识当前栈帧的起始地址，栈对象就位于fp偏移0x10的地方。

调用构造函数Base::Base(int)时，传入的参数如下
- 第1个参数是栈对象地址x0 = x29 + 0x10
- 第2个参数是w1 = 1

### 2.1.3 析构
对于栈对象，离开作用域前，将自动调用析构函数。

```asm
=> 0x0000aaaaaaaaadcc <+40>:	add	x0, x29, #0x10
   0x0000aaaaaaaaadd0 <+44>:	bl	0xaaaaaaaab08c <Base::~Base()>
```

调用析构函数很简单，传入栈对象地址，直接调用Base::~Base()即可。


## 2.2 堆对象
### 2.2.1 测试代码
```cpp
void heap() {
  Base *heap_obj = new Base(2);

  delete heap_obj;
}
```

heap()的反汇编如下
```asm
(gdb) disas
Dump of assembler code for function heap():
   0x0000aaaaaaaaaee0 <+0>:	stp	x29, x30, [sp, #-48]!
   0x0000aaaaaaaaaee4 <+4>:	mov	x29, sp
   0x0000aaaaaaaaaee8 <+8>:	str	x19, [sp, #16]
   0x0000aaaaaaaaaeec <+12>:	mov	x0, #0x4                   	// #4
   0x0000aaaaaaaaaef0 <+16>:	bl	0xaaaaaaaaad20 <_Znwm@plt>
   0x0000aaaaaaaaaef4 <+20>:	mov	x19, x0
   0x0000aaaaaaaaaef8 <+24>:	mov	w1, #0x2                   	// #2
   0x0000aaaaaaaaaefc <+28>:	mov	x0, x19
   0x0000aaaaaaaaaf00 <+32>:	bl	0xaaaaaaaab098 <Base::Base(int)>
=> 0x0000aaaaaaaaaf04 <+36>:	str	x19, [x29, #40]
   0x0000aaaaaaaaaf08 <+40>:	ldr	x19, [x29, #40]
   0x0000aaaaaaaaaf0c <+44>:	cmp	x19, #0x0
   0x0000aaaaaaaaaf10 <+48>:	b.eq	0xaaaaaaaaaf24 <heap()+68>  // b.none
   0x0000aaaaaaaaaf14 <+52>:	mov	x0, x19
   0x0000aaaaaaaaaf18 <+56>:	bl	0xaaaaaaaab0bc <Base::~Base()>
   0x0000aaaaaaaaaf1c <+60>:	mov	x0, x19
   0x0000aaaaaaaaaf20 <+64>:	bl	0xaaaaaaaaad10 <_ZdlPv@plt>
   0x0000aaaaaaaaaf24 <+68>:	nop
   0x0000aaaaaaaaaf28 <+72>:	ldr	x19, [sp, #16]
   0x0000aaaaaaaaaf2c <+76>:	ldp	x29, x30, [sp], #48
   0x0000aaaaaaaaaf30 <+80>:	ret
End of assembler dump.
```

### 2.2.2 构造
对于堆对象，通过**new运算符**显式构造。
- 调用operator new分配内存
- 调用构造函数
- 返回堆对象指针


先看分配内存
```asm
   0x0000aaaaaaaaaeec <+12>:	mov	x0, #0x4                   	// #4
   0x0000aaaaaaaaaef0 <+16>:	bl	0xaaaaaaaaad20 <_Znwm@plt>
   0x0000aaaaaaaaaef4 <+20>:	mov	x19, x0
```
Base类只有一个数据成员int m_var, 在编译期能获知其实例大小为4。 然后传给operator new函数去分配4字节大小的堆内存。若分配成功，则将堆内存地址保存到x19

operator new的实现
> 源文件: gcc/libstdc++-v3/libsupc++/new_op.cc
```cpp
_GLIBCXX_WEAK_DEFINITION void *
operator new (std::size_t sz) _GLIBCXX_THROW (std::bad_alloc)
{
  void *p; 

  /* malloc (0) is unpredictable; avoid it.  */
  if (sz == 0)
    sz = 1;

  while (__builtin_expect ((p = malloc (sz)) == 0, false))
    {   
      new_handler handler = std::get_new_handler (); 
      if (! handler)
        _GLIBCXX_THROW_OR_ABORT(bad_alloc());
      handler (); 
    }   

  return p;
}
```

operator new实现如下
- 调用c库函数**malloc**()尝试分配内存。若分配成功， 则返回。
- malloc()分配失败后， 会先获取new handler(通过std::set_new_handler()设置)。若handler不为空，则调用handler，否则抛出**bad_alloc**异常。
  ```
  terminate called after throwing an instance of 'std::bad_alloc'
    what():  std::bad_alloc
  Aborted (core dumped)
  ```

> 注: 若在Base内将operator new重载为private, 则该类不能生成堆对象。

再看调用构造函数
```asm
   0x0000aaaaaaaaaef8 <+24>:	mov	w1, #0x2                   	// #2
   0x0000aaaaaaaaaefc <+28>:	mov	x0, x19
   0x0000aaaaaaaaaf00 <+32>:	bl	0xaaaaaaaab098 <Base::Base(int)>
```

调用构造函数Base::Base(int)时，传入的参数如下
- 第1个参数是operator new返回的堆内存地址x0
- 第2个参数是w1 = 2

最后将堆对象指针存储到栈内
```asm
=> 0x0000aaaaaaaaaf04 <+36>:	str	x19, [x29, #40]
```

### 2.2.3 析构
对于堆对象，通过**delete运算符**显式析构。
- 调用堆对象的析函数
- 调用operator delete释放内存

先看调用堆对象的析构函数
```asm
   0x0000aaaaaaaaaf08 <+40>:	ldr	x19, [x29, #40]
   0x0000aaaaaaaaaf0c <+44>:	cmp	x19, #0x0
   0x0000aaaaaaaaaf10 <+48>:	b.eq	0xaaaaaaaaaf24 <heap()+68>  // b.none
   0x0000aaaaaaaaaf14 <+52>:	mov	x0, x19
   0x0000aaaaaaaaaf18 <+56>:	bl	0xaaaaaaaab0bc <Base::~Base()>
```

检查堆对象指针是否为空
- 若是，则跳过析构函数和operator delete 函数的调用(**delete空指针没问题**)
- 否则，调用析构函数

再看调用operator delete释放堆内存
```asm
   0x0000aaaaaaaaaf1c <+60>:	mov	x0, x19
   0x0000aaaaaaaaaf20 <+64>:	bl	0xaaaaaaaaad10 <_ZdlPv@plt>
```

最后看下operator delete的实现
> 源文件: gcc/libstdc++-v3/libsupc++/del_op.cc
```cpp
_GLIBCXX_WEAK_DEFINITION void
operator delete(void* ptr) _GLIBCXX_USE_NOEXCEPT
{
  std::free(ptr);
}
```

可以看到，operator delete直接调用了c库的free()函数

# 3. 总结
- **栈对象**位于**stack**，定义栈对象时自动构造完成初始化，超出作用域后自动析构，开发人员不必刻意维护栈对象。
- **堆对象**位于**heap**, 需要new/delete(间接调用malloc()/free())显式构造和析构，如果没有及时析构容易引起内存泄露，可借助**智能指针**加强堆对象的内存管理。

---

![程序员自我修养](http://ww1.sinaimg.cn/large/005Kyrj9ly1gbvsonijdoj3076076wex.jpg)

<center>
程序员自我修养(ID: dumphex)
</center>

---
