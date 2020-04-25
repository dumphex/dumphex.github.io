---
title: 单例模式
date: 2020-04-18 17:27:35
tags:
- singleton
- 静态对象
- 局部静态对象
categories: 设计模式
---

总结单例模式在C++下的实现

<!-- more -->

## 1. 介绍
[单例模式](https://en.wikipedia.org/wiki/Singleton_pattern), 是23种GOF设计模式之一, 属于**创建型**. 顾名思义, 单例模式就是一个类只能实例化出一个对象.

考虑两个问题

**1.1 如何保证只能实例出一个对象?**
- 将构造函数设为private, 防止在类外生成栈对象/堆对象
- 将赋值运算符设为private, 防止赋值对象(上面构造函数为private已经间接确保了不可能赋值).

**1.2 外界如何获取单例?**
- 提供public的静态方法getInstance()
- 保证线程安全


## 2. 实现方法

### 2.1 饿汉式
饿汉式, 就是不管是否用到, 默认都会创建.

```cpp
// SingletonEager
class SingletonEager {
 public:
  static SingletonEager & getInstance() {
    return m_instance;
  }

 private:
  static SingletonEager m_instance;

  SingletonEager() {
    std::cout << __FUNCTION__ << " is caled. " << std::endl;
  }

  ~SingletonEager() {
    std::cout << __FUNCTION__ << " is caled. " << std::endl;
  }

  SingletonEager(const SingletonEager & s);
  SingletonEager& operator =(const SingletonEager & s);
};

SingletonEager SingletonEager::m_instance;
```

两点说明:
- 这里使用**类的静态变量**来实现. 静态对象在main()前被构造执行初始化, 具体可参考[C++的全局对象](https://dumphex.github.io/2020/03/15/global-object/).
- 但存在一个问题: 如果该类被另一个全局对象/静态对象使用, 但这两个类不在同一源文件(不同的编译单元), 则可能存在问题. 因为**不同编译单元的non-local对象的初始化顺序是不确定的**.


### 2.2 懒汉式
懒汉式, 就是第一次调用到的时候才去创建.

```cpp
// SingletonLazy
class SingletonLazy {
 public:
  static std::unique_ptr<SingletonLazy> & getInstance() {
    std::lock_guard<std::mutex> lck(m_mtx);
    if(m_instance == nullptr) {
      m_instance.reset(new SingletonLazy());
    }

    return m_instance;
  }

  ~SingletonLazy() {
    std::cout << __FUNCTION__ << " is caled. " << std::endl;
  }

 private:
  static std::mutex m_mtx;
  static std::unique_ptr<SingletonLazy> m_instance;

  SingletonLazy() {
    std::cout << __FUNCTION__ << " is caled. " << std::endl;
  }

  SingletonLazy(const SingletonLazy & s);
  SingletonLazy& operator =(const SingletonLazy & s);
};

std::mutex SingletonLazy::m_mtx;
std::unique_ptr<SingletonLazy> SingletonLazy::m_instance;
```

两点说明
- 使用智能指针, 保证程序退出前堆对象能正确释放
- getInstance()需要加锁, 用于保证多线程安全


### 2.3 局部静态对象
Effective C++一书中item4(确保对象初始化)中, 提到了Scott Meyer版本的实现

```
// local static
class SingletonLocalStatic {
 public:
  static SingletonLocalStatic & getInstance() {
    static SingletonLocalStatic instance;
    return instance;
  }

 private:
  SingletonLocalStatic() {
     std::cout << __FUNCTION__ << " is caled. " << std::endl;
  }

  ~SingletonLocalStatic() {
     std::cout << __FUNCTION__ << " is caled. " << std::endl;
  }

  SingletonLocalStatic(const SingletonLocalStatic & s);
  SingletonLocalStatic& operator =(const SingletonLocalStatic & s);
};
```

C++11/较新的gcc编译器, 能保证局部静态对象的线程安全, 具体实现原理可参考之前研究过的[C++的局部静态对象](https://dumphex.github.io/2020/03/09/local-static-object/)

## 3. 总结
|实现方式|说明|
|--------|----|
|饿汉式|若被其它编译单元的全局对象/静态对象使用, 有可能存在初始化顺序问题|
|懒汉式|加锁影响性能|
|局部静态对象|C++11/gcc较新版本才支持, 推荐使用|

---

![程序员自我修养](http://ww1.sinaimg.cn/large/005Kyrj9ly1gbvsonijdoj3076076wex.jpg)

<center>
程序员自我修养(ID: dumphex)
</center>

---
