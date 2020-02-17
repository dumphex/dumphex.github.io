#!/bin/bash

function preview()
{
  hexo clean && hexo g && hexo s
}

function deploy()
{
  hexo clean && hexo g && hexo d
}

function update()
{
  git pull && git submodule init && git submodule update
}
