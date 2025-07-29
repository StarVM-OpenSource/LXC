#!/bin/bash

text="你在期待什么？"
for ((i=0; i<${#text}; i++)); do
  echo -n "${text:$i:1}"
  sleep 0.1
done
echo