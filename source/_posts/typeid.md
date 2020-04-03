---
title: typeid
date: 2020-04-03 15:09:08
tags:
- typeid
- type_info
categories: C/C++
---

本文分析C++中typeid的实现原理

<!-- more -->

## 1. 前言
### 1.1 typeid
C++里面的typeid是个**运算符**，返回一个[std::type_info](http://www.cplusplus.com/reference/typeinfo/type_info/)常对象的引用，用于标识对象所属的类型。

### 1.2 std::type_info
- 实现位于/usr/include/c++/7/typeinfo
- 析构函数为virtual
- 有一个保护成员const char *__name, 指向对象的类型名称
- 可以通过name()方法打印出对象的真实类型.
  ```
    const char* name() const _GLIBCXX_NOEXCEPT
    { return __name[0] == '*' ? __name + 1 : __name; }
  ```

## 2. 调试分析

### 2.1 测试环境
- Linux ubuntu18arm64 4.15.0-76-generic #86-Ubuntu SMP Fri Jan 17 17:25:58 UTC 2020 aarch64 aarch64 aarch64 GNU/Linux
- gcc version 7.4.0 (Ubuntu/Linaro 7.4.0-1ubuntu1~18.04.1)
- C++11


### 2.2 基本数据类型

测试代码
```cpp
#define PRINT(x) std::cout << "typeid("#x").name() = \"" << typeid(x).name() << "\"" << std::endl;

void test_fundamental_type() {
  int i = 1;
  int *p = &i;
  const float f = 2.0;
  volatile double d = 3.0;

  PRINT(i);
  PRINT(p);
  PRINT(f);
  PRINT(d);
}
```

运行结果
```shell
typeid(i).name() = "i"
typeid(p).name() = "Pi"
typeid(f).name() = "f"
```

可以看到，返回的类型名字中const/volatile等限定符都不存在了。

下面以变量i为例， 描述typeid(i).name()的实现原理.

汇编代码如下
```asm
   ... ...
   0x0000aaaaaaaab504 <+64>:	adrp	x0, 0xaaaaaaabc000
   0x0000aaaaaaaab508 <+68>:	ldr	x0, [x0, #3984]
   0x0000aaaaaaaab50c <+72>:	bl	0xaaaaaaaab840 <std::type_info::name() const>
   ... ...
```

获取std::type_info对象地址
```asm
(gdb) x/1xg 0xaaaaaaabc000 + 3984
0xaaaaaaabcf90:	0x0000fffff7fc3d90
```

查看std::type_info对象
```asm
(gdb) x/2xg 0x0000fffff7fc3d90
0xfffff7fc3d90 <_ZTIi>:	0x0000fffff7fc38c0	0x0000fffff7f771c0
```

查看类型名称
```asm
(gdb) p (char*)0x0000fffff7f771c0
$1 = 0xfffff7f771c0 <typeinfo name for int> "i"
```

变量i的type_info对象及其name, 位于libstdc++.so
```shell
... ...
fffff7e3e000-fffff7fb2000 r-xp 00000000 fd:00 1311408                    /usr/lib/aarch64-linux-gnu/libstdc++.so.6.0.25
fffff7fb2000-fffff7fc2000 ---p 00174000 fd:00 1311408                    /usr/lib/aarch64-linux-gnu/libstdc++.so.6.0.25
fffff7fc2000-fffff7fcc000 r--p 00174000 fd:00 1311408                    /usr/lib/aarch64-linux-gnu/libstdc++.so.6.0.25
fffff7fcc000-fffff7fce000 rw-p 0017e000 fd:00 1311408                    /usr/lib/aarch64-linux-gnu/libstdc++.so.6.0.25
... ...
```

### 2.3 类型确定的类类型
测试代码
```cpp
  Derived d;
  PRINT(d);
```

运行结果
```shell
typeid(d).name() = "7Derived"
```

汇编代码如下
```asm
   ... ...
   0x0000aaaaaaaab68c <+64>:	adrp	x0, 0xaaaaaaabc000
   0x0000aaaaaaaab690 <+68>:	add	x0, x0, #0xcb0
   0x0000aaaaaaaab694 <+72>:	bl	0xaaaaaaaab840 <std::type_info::name() const>
   ... ...
```

查看对象d的std::type_info对象
```asm
(gdb) x/2xg 0xaaaaaaabc000 + 0xcb0
0xaaaaaaabccb0 <_ZTI7Derived>:	0x0000fffff7fc4278	0x0000aaaaaaaabab8
```

查看类型名称
```asm
(gdb) p (char*)0x0000aaaaaaaabab8
$2 = 0xaaaaaaaabab8 <typeinfo name for Derived> "7Derived"
```

编译器在编译期间已经知道对象d的std::type_info对象地址

### 2.4 类型不确定的类类型

基类指针或引用, 无法确定当前对象是Base对象还是Derived对象.

测试代码
```cpp
  Base *pb = &d;
  PRINT(*pb);
```

运行结果
```shell
typeid(*pb).name() = "7Derived"
```

汇编代码如下
```asm
   ... ...
   0x0000aaaaaaaab6f4 <+168>:	ldr	x0, [x29, #32]
   0x0000aaaaaaaab6f8 <+172>:	cmp	x0, #0x0
   0x0000aaaaaaaab6fc <+176>:	b.eq	0xaaaaaaaab71c <test_class_type()+208>  // b.none
   0x0000aaaaaaaab700 <+180>:	ldr	x0, [x0]
   0x0000aaaaaaaab704 <+184>:	ldur	x0, [x0, #-8]
   0x0000aaaaaaaab708 <+188>:	bl	0xaaaaaaaab840 <std::type_info::name() const>
   0x0000aaaaaaaab70c <+192>:	mov	x1, x0
   0x0000aaaaaaaab710 <+196>:	mov	x0, x19
   0x0000aaaaaaaab714 <+200>:	bl	0xaaaaaaaab330 <_ZStlsISt11char_traitsIcEERSt13basic_ostreamIcT_ES5_PKc@plt>
   0x0000aaaaaaaab718 <+204>:	b	0xaaaaaaaab720 <test_class_type()+212>
   0x0000aaaaaaaab71c <+208>:	bl	0xaaaaaaaab350 <__cxa_bad_typeid@plt>
   ... ...
```

typeid(*pb)的实现流程如下
- 先获取*pb对象的vptr
```asm
(gdb) x/4xg 0xfffffffff220 + 32
0xfffffffff240:	0x0000fffffffff248	0x0000aaaaaaabcc80
0xfffffffff250:	0x0000000000000000	0xa70531c2abcbb300

(gdb) x/1xg 0x0000fffffffff248
0xfffffffff248:	0x0000aaaaaaabcc80
```

- 再读取vtable[-1], 获取std::type_info对象
```asm
(gdb) x/1xg 0x0000aaaaaaabcc80 - 8
0xaaaaaaabcc78 <_ZTV7Derived+8>:	0x0000aaaaaaabccb0

(gdb) x/2xg 0x0000aaaaaaabccb0
0xaaaaaaabccb0 <_ZTI7Derived>:	0x0000fffff7fc4278	0x0000aaaaaaaabab8
```

- 查看类型名称
```asm
(gdb) p (char *)0x0000aaaaaaaabab8
$3 = 0xaaaaaaaabab8 <typeinfo name for Derived> "7Derived"
```

## 3. 总结 
- 对**基本数据类型**或**类型确定的类类型**, typeid(obj)对应的std::type_info对象地址在**编译期间**已经确定
- 对**类型不确定的类类型**(基类指针或引用, 多态), typeid(obj)是**运行期间**通过当前对象找到vptr, 最后在vtable[-1]找到obj对应的std::type_info对象地址

---

![程序员自我修养](http://ww1.sinaimg.cn/large/005Kyrj9ly1gbvsonijdoj3076076wex.jpg)

<center>
程序员自我修养(ID: dumphex)
</center>

---
