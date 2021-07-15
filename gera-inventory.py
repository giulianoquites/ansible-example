#!/usr/bin/python
#EXAMPLE:

#CMD>> cat example_csv.csv
#name;ip;group;zone
#host01;10.10.0.2;prod;dc1
#host02;10.10.0.3;prod;dc2
#host03;10.10.0.4;test;dc1
#host04;10.10.0.5;test;dc2
#host05;10.10.0.6;dev;dc1
#host06;10.10.0.7;dev;dc2

#CMD>> python gera-inventory.py example_csv.csv 
#[prod]
#host1
#host2
#[dc1]
#host1
#host3
#host5
#[dc2]
#host2
#host4
#host6
#[test]
#host3
#host4
#[dev]
#host5
#host6
#
#INFO:Generated Ansible host inventory file: inventory_xx.ini



import csv
import sys
import os
 
if len(sys.argv) <= 1:
   print "Usage:" +sys.argv[0]+" input-filename"
   sys.exit(1) 
groups = []
envs = set()
hosts_ini = {}

csvname = sys.argv[1]
scriptpath = os.path.dirname(sys.argv[0])
ansible_ini = os.path.join(scriptpath, 'inventory_xx.ini')

lines = []
hosts_text = ''
with open(csvname) as csvfile:
    reader = csv.DictReader(csvfile, delimiter=';')
    for row in reader:
        line = row['name'].strip() 
        for g in row['group'].strip().split(';'):
          g = g.strip()
          if (not g in groups):
            groups.append(g)
          hosts_ini.setdefault(g, []).append(line)
        for g in row['zone'].strip().split(';'):
          g = g.strip()
          if (not g in groups):
            groups.append(g)
          hosts_ini.setdefault(g, []).append(line)

for g in groups:
   hosts_text+='\n['+g+']\n'
   hosts_text+='\n'.join(hosts_ini[g])
   hosts_text+='\n'

all_text = hosts_text
print all_text
with open(ansible_ini,'w') as new_ini_file:
    new_ini_file.write(all_text)   
print "INFO:Generated Ansible host inventory file: " + ansible_ini  
