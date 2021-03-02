import ok
from time import sleep
import numpy as np

fp = ok.FrontPanel()
n_devices = fp.GetDeviceCount()

for i in range(n_devices):
    s = fp.GetDeviceListSerial(i)
    fp.OpenBySerial(s)
    if fp.GetDeviceID() == 'KRbDigi01':
        break

fp.ConfigureFPGA('./line_trigger_test.bit')
sleep(1)

times = []
for i in range(1000):
   fp.UpdateWireOuts()
   times.append(1e-6 * fp.GetWireOutValue(0x20))
   sleep(0.02)

np.savetxt('60Hz_data.txt', times)
fp.Close()
