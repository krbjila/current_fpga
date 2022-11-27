from numpy.core.fromnumeric import searchsorted
import pyvisa
import sys
import numpy as np
from time import sleep

from matplotlib import pyplot as plt

def acquire(dev, span):
    dev.write_termination = u'\n'
    dev.clear()
    dev.write("STRF 0")
    dev.flush(pyvisa.constants.VI_WRITE_BUF)
    dev.write("SPAN {}".format(span))
    dev.write("NAVG 100")

    dev.write("STRT")


    complete = False
    for _ in range(20):
        sleep(1)
        if bool(dev.query("FFTS? 4")):
            complete = True
            break

    if not complete:
        raise(TimeoutError("Acquisition timed out!"))

    bin0 = float(dev.query('BVAL? 1,0'))
    bin1 = float(dev.query('BVAL? 1,1'))
    raw_data = dev.query('SPEC? 0')

    data = np.fromstring(raw_data, sep=',')[:-1]
    xs = np.arange(bin0, bin0+(bin1-bin0)*len(data), bin1-bin0)
    return np.transpose(np.vstack((xs, data)))


if len(sys.argv) < 2:
    raise(RuntimeError("Must specify filename as argument"))
fname = str(sys.argv[1])
rm = pyvisa.ResourceManager()
resources = [i for i in rm.list_resources() if "GPIB" in i]
if len(resources):
    dev = rm.open_resource(resources[0], timeout=5000)
    output_low = acquire(dev, 14) # 3.125 kHz span
    output_high = acquire(dev, 19) # 100 kHz span
    end_low = output_low[-1, 0]
    idx = searchsorted(output_high[:,0], end_low)
    merged = np.vstack((output_low, output_high[idx:,:]))
    np.savetxt(fname, merged)
    dev.close()

    plt.loglog(merged[:, 0], merged[:, 1])
    plt.show()
else:
    raise(RuntimeError("Could not connect to FFT machine"))