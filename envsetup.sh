#!/bin/bash

function preview()
{
  hexo clean && hexo g && hexo s
}

function deploy()
{
  hexo clean && hexo g && hexo d
}
