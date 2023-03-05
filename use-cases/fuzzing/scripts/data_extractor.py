import sys

def get_plot_data(filename):
	with open(filename, 'rt') as fd:
		lines = [l.strip() for l in fd.readlines()]
	return lines

def extract(lines):
	res = []

	start_time = int(lines[1].split(',')[0])

	for l in lines[1:]:
		tp = l.split(',')
		t = int(tp[0]) - start_time
		exec = float(tp[-1])
		res.append(f'{t} {exec}')

	return res

def write(res, filename):
	with open(filename, 'wt') as fd:
		fd.write('\n'.join(res))

def main():
	lines = get_plot_data(sys.argv[1])
	res = extract(lines)
	write(res, sys.argv[2])

if __name__ == "__main__":
	main()

