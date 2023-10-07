#!/apps/python3/3.10.0/bin/python3
import numpy as np
import subprocess

g_tensor = str(subprocess.getoutput('grep -A 3 "gtensor_total" cp2k-GTENSOR-1.data | tail -3 | tr -d "a-zA-Z="'))
g_tensor = g_tensor.strip("\n").split()
g_tensor = list(map(float, g_tensor))
g_tensor = np.array(g_tensor).reshape(3, 3)
print(g_tensor)
print(np.linalg.eigvalsh(g_tensor))
