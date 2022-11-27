import pyvisa
import numpy as np
from matplotlib import pyplot as plt
from time import sleep

# Connect to scope
rm = pyvisa.ResourceManager()
resources = rm.list_resources()
id = [i for i in resources if "MS5" in i][0]
scope = rm.open_resource(id)

# Setup acquisition
scope.write(":CHAN1:SCAL 0.2")
scope.write(":CHAN1:POS 0")

scope.write(":TIM:DEL:ENAB 0")
scope.write(":TIM:OFF 0")
scope.write(":TIM:MODE MAIN")
scope.write(":TIM:SCAL 0.00005")

scope.write(":TRIG:MODE EDGE")
scope.write(":TRIG:COUP DC")
scope.write(":TRIG:SWE SING")
scope.write(":TRIG:EDGE:SOUR CHAN1")
scope.write(":TRIG:EDGE:SLOP POS")
scope.write(":TRIG:EDGE:LEV 0")

# Save data
scope.write(":WAV:SOUR CHAN1")
scope.write(":WAV:MODE NORM")
scope.write(":WAV:FORM ASC")
scope.write(":WAV:POINT 1000")

scope.flush(pyvisa.constants.VI_WRITE_BUF)
while True:
    sleep(0.1)
    result = scope.query(":TRIG:STAT?")
    if "STOP" in result:
        break

dx = float(scope.query(":WAV:XINC?"))
x0 = float(scope.query(":WAV:XOR?"))
data = str(scope.query(":WAV:DATA?"))
n_bytes = int(data[1])
data = np.array(data[n_bytes+2:-2].split(','), np.float64)
n_points = len(data)
times = np.linspace(x0, x0+(n_points-1)*dx, n_points)

# Disconnect from scope
scope.close()

# Display data
start_V = np.mean(data[:100])
end_V = np.mean(data[-100:])
lower_tenth = start_V + (end_V - start_V)/10.0
upper_tenth = start_V + 2.0*(end_V - start_V)/10.0
# ramp_start = [i for (i, v)]

print("Start: ", start_V)
print("End: ", end_V)


fig, ax = plt.subplots()
ax.plot(times, data)
ax.xaxis.set_major_locator(plt.MaxNLocator(5))
ax.ticklabel_format(axis='x', style='sci')
ax.set_xlabel("Time (s)")
ax.set_ylabel("Voltage (V)")
plt.show()