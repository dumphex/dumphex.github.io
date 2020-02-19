---
title: c++左值引用
date: 2020-02-19 13:40:48
tags:
- refererence
- 左值引用
categories: C/C++
---

和C语言相比，C++引入了左值引用，本文介绍左值引用的实现原理。

<!-- more -->

# 1. 测试
## 1.1 编译环境
- aarch64-linux-gnu-g++ 6.3.1

## 1.2 C++ code
```cpp
void test_reference(int &ra) {
  ra = 2;
}


void test_pointer(int *pa) {
  *pa = 3;
}

int main(int argc, char *argv[]) {
  int a = 1;

  int &ra = a;
  ra = 2;

  int *pa = &a;
  *pa = 3;

  test_reference(a);
  test_pointer(&a);

  return 0;
}
```


## 1.3 汇编code
```asm
0000000000400770 <_Z14test_referenceRi>:
  400770:	d10043ff 	sub	sp, sp, #0x10
  400774:	f90007e0 	str	x0, [sp,#8]
  400778:	f94007e0 	ldr	x0, [sp,#8]
  40077c:	52800041 	mov	w1, #0x2                   	// #2
  400780:	b9000001 	str	w1, [x0]
  400784:	d503201f 	nop
  400788:	910043ff 	add	sp, sp, #0x10
  40078c:	d65f03c0 	ret

0000000000400790 <_Z12test_pointerPi>:
  400790:	d10043ff 	sub	sp, sp, #0x10
  400794:	f90007e0 	str	x0, [sp,#8]
  400798:	f94007e0 	ldr	x0, [sp,#8]
  40079c:	52800061 	mov	w1, #0x3                   	// #3
  4007a0:	b9000001 	str	w1, [x0]
  4007a4:	d503201f 	nop
  4007a8:	910043ff 	add	sp, sp, #0x10
  4007ac:	d65f03c0 	ret

00000000004007b0 <main>:
  4007b0:	a9bc7bfd 	stp	x29, x30, [sp,#-64]!
  4007b4:	910003fd 	mov	x29, sp
  4007b8:	b9001fa0 	str	w0, [x29,#28]
  4007bc:	f9000ba1 	str	x1, [x29,#16]
  4007c0:	52800020 	mov	w0, #0x1                   	// #1
  4007c4:	b9002fa0 	str	w0, [x29,#44]
  4007c8:	9100b3a0 	add	x0, x29, #0x2c
  4007cc:	f9001fa0 	str	x0, [x29,#56]
  4007d0:	f9401fa0 	ldr	x0, [x29,#56]
  4007d4:	52800041 	mov	w1, #0x2                   	// #2
  4007d8:	b9000001 	str	w1, [x0]
  4007dc:	9100b3a0 	add	x0, x29, #0x2c
  4007e0:	f9001ba0 	str	x0, [x29,#48]
  4007e4:	f9401ba0 	ldr	x0, [x29,#48]
  4007e8:	52800061 	mov	w1, #0x3                   	// #3
  4007ec:	b9000001 	str	w1, [x0]
  4007f0:	9100b3a0 	add	x0, x29, #0x2c
  4007f4:	97ffffdf 	bl	400770 <_Z14test_referenceRi>
  4007f8:	9100b3a0 	add	x0, x29, #0x2c
  4007fc:	97ffffe5 	bl	400790 <_Z12test_pointerPi>
  400800:	52800000 	mov	w0, #0x0                   	// #0
  400804:	a8c47bfd 	ldp	x29, x30, [sp],#64
  400808:	d65f03c0 	ret
```

# 2 分析
## 2.1 普通变量

普通变量a的赋值
```
int a = 1;
```

对应汇编
```
  4007c0:	52800020 	mov	w0, #0x1                   	// #1
  4007c4:	b9002fa0 	str	w0, [x29,#44]
```

变量a是局部变量，存储在栈内fp + 44的地方，大小为4

## 2.2 引用

先看引用的初始化
```
  int &ra = a;
```

对应汇编
```
  4007c8:	9100b3a0 	add	x0, x29, #0x2c
  4007cc:	f9001fa0 	str	x0, [x29,#56]
```
也就是，引用ra本身存储在栈内fp + 56的地方，大小为8, 里面存储的是变量a的地址即fp + 44


再看引用的赋值
```
  ra = 2;
```

对应汇编
```
  4007d0:	f9401fa0 	ldr	x0, [x29,#56]
  4007d4:	52800041 	mov	w1, #0x2                   	// #2
  4007d8:	b9000001 	str	w1, [x0]
```
也就是，先将引用对应的变量的地址load出来， 再将具体赋的值store回变量的地址。

## 2.3 指针

先看指针的初始化
```
  int *pa = &a;
```

对应汇编
```
  4007dc:	9100b3a0 	add	x0, x29, #0x2c
  4007e0:	f9001ba0 	str	x0, [x29,#48]
```
指针pa指向普通变量a, 其存储在栈内fp + 48的地方， 大小为8, 存储的内容为变量a的地址即fp + 44

再看解引用指针
```
  *pa = 3;
```

对应汇编
```
  4007e4:	f9401ba0 	ldr	x0, [x29,#48]
  4007e8:	52800061 	mov	w1, #0x3                   	// #3
  4007ec:	b9000001 	str	w1, [x0]
```
和引用类似，先将指针指向的变量的地址load出来， 再将具体赋的值store回变量的地址。

## 2.4 引用和指针作为形参
从前面test_reference和test_pointer的汇编代码对比来看
- 引用和指针传参，实现是相同的， 传入的都是变量a的地址
- 修改引用或解引用指针，都会反映到变量a

# 3. 总结
- 从语法上讲，引用是变量的别名。 但从编译器实现来看， 为其分配了存储空间，初始化为指定变量的地址。
- 引用可以看作是constant pointer, 对引用的访问，可看作被引用变量的间接访问。

---

![程序员自我修养](http://ww1.sinaimg.cn/large/005Kyrj9ly1gbvsonijdoj3076076wex.jpg)

<center>
程序员自我修养(ID: dumphex)
</center>

---

