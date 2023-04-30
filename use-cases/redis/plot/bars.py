#!/usr/bin/env python3

import sys
import os
import pandas as pd
import numpy as np
import matplotlib
import matplotlib.pyplot as plt
import matplotlib.ticker as mticker

matplotlib.rcParams['pdf.fonttype'] = 42
matplotlib.rcParams['ps.fonttype'] = 42

"""
average line:
- keys,fork avg, fork min, fork max, save avg, save min, save max
e.g.: 10000,11.286014,10.531396,12.459998,41.185169,40.519263,42.347366
"""

class PlotValue(object):
	def __init__(self, avg, minval, maxval):
		self.avg = avg
		self.min = minval
		self.max = maxval
	def __repr__(self):
		return "(%f,%f,%f)" % (self.avg, self.min, self.max)

def read_data_from_file(data_dir, is_vm_data=False):
	filename = os.path.join(data_dir, "average")
	if not os.path.isfile(filename):
		print("File %s does not exist!" % filename)
		sys.exit(-2)
	f = open(filename, 'r')
	data = {}
	while True:
		line = f.readline()
		if not line:
			break
		values = line.split(',')
		keys_num = int(values[0])
		results = { "fork"        : PlotValue(float(values[1]), float(values[2]), float(values[3])),
		            "save"        : PlotValue(float(values[4]), float(values[5]), float(values[6]))
		}
		if is_vm_data:
			results["userspace"] = PlotValue(float(values[7]), float(values[8]), float(values[9]))
		data[keys_num] = results 
	f.close()
	return data

def read_data(data_dir):
	process_dir = os.path.join(data_dir, "process")
	if not os.path.isdir(process_dir):
		print("process subdir does not exist!")
		sys.exit(-2)
	vm_dir = os.path.join(data_dir, "vm")
	if not os.path.isdir(vm_dir):
		print("vm subdir does not exist!")
		sys.exit(-2)

	process_data = read_data_from_file(process_dir)
	vm_data = read_data_from_file(vm_dir, is_vm_data=True)
	#TODO compare keys
	return process_data, vm_data

def get_lists(data, is_vm_data=False):
	values1, userspace1, save1 = [], [], []
	for keys_num in sorted(data.keys()):
		results = data[keys_num]

		value = results["fork"]
		values1.append(value.avg)

		value = results["save"]
		save1.append(value.avg)

		if is_vm_data:
			value = results["userspace"]
			userspace1.append(value.avg)

	return values1, userspace1, save1

def usage_and_exit():
	print("Usage: %s <directory>" % sys.argv[0])
	sys.exit(-2)

if len(sys.argv) != 2:
	usage_and_exit()
mydir = sys.argv[1]
if not os.path.isdir(mydir):
	usage_and_exit()


process_data, vm_data = read_data(mydir)
d = {}
d["p1"], _,                d["p1save"] = get_lists(process_data)
d["v1"], d["v1userspace"], d["v1save"] = get_lists(vm_data, is_vm_data=True)
df = pd.DataFrame(data=d)

#fig = plt.figure(figsize=(20, 10))
fig = plt.figure()
plt.xlabel("Keys number")
plt.ylabel("Milliseconds")
plt.grid(axis='y', linestyle=':')

ax=plt.gca()
ax.set_yscale('log')
ax.set_ylim([0.01, 10000])
#ax.yaxis.set_major_formatter(mticker.ScalarFormatter())
ax.set_yticklabels([10**i for i in range(-3,4)])
ax.set_xticklabels([ str(i) for i in sorted(vm_data.keys()) ])
ax.set_xticks([ i for i in range(len(vm_data.keys())) ])

plt.xticks(fontsize=9)

x_labels = [ str(i) for i in sorted(vm_data.keys()) ]
X = np.arange(len(x_labels))

p1_bar_list = [
	plt.bar(X - 0.30, df.p1, width=0.20, color='#80D083')
]

p1save_bar_list = [
	plt.bar(X - 0.10, df.p1save, width=0.20, color='#4C9C4E')
]

v1_bar_list = [
	plt.bar(X + 0.10, df.v1, width=0.20, color='#E5E977'),
	plt.bar(X + 0.10, df.v1 - df.v1userspace, width=0.20, color='#8C98D5')
]

v1save_bar_list = [
	plt.bar(X + 0.30, df.v1save, width=0.20, color='#4F66DB')
]

plt.legend(
	(p1_bar_list[0], p1save_bar_list[0], v1_bar_list[1], v1save_bar_list[0], v1_bar_list[0]),
	('VM process fork', 'VM process save', 'Unikraft clone', 'Unikraft save', 'userspace operations'),
frameon=False)
#plt.show()
output_file = os.path.join(mydir, "bars.py.pdf")
fig.savefig(output_file, bbox_inches='tight')
