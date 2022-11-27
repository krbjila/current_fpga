import pyvisa
import numpy as np
from matplotlib import pyplot as plt
from time import sleep
import sys
import ok
import numpy as np

VOLTAGE_RANGE = (-10., 10.)
DAC_BITS = 16
N_CHANNELS = 8
# CLK = 0.25 * 48e6 / (8.*2. + 2. + 1.)
CLK = 0.25 * 50e6 / (8.*2. + 2. + 1.)
# CLK = 48e6 / (8.*2. + 2.)

mode_ints = {'idle': 0, 'load': 1, 'run': 2}
mode_wire = 0x00
sequence_pipe = 0x80
channel_mode_wire = 0x09
manual_voltage_wires = [0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]


# bitfile = "dac.bit"
bitfile = "C:\\Users\\Ye Lab\\Desktop\\Cal\\current_fpga\\dac_lower_drive\\dac.bit"
# bitfile = "blinky2.bit"

def time_to_ticks(clk, time):
    return max(int(abs(clk*time)), 1)

def voltage_to_signed(voltage):
    voltage_span = float(max(VOLTAGE_RANGE) - min(VOLTAGE_RANGE))
    voltage = sorted([-voltage_span, voltage, voltage_span])[1]
    return int(voltage/voltage_span*(2**DAC_BITS-1))

def voltage_to_unsigned(voltage):
    min_voltage = min(VOLTAGE_RANGE)
    max_voltage = max(VOLTAGE_RANGE)
    voltage_span = float(max(VOLTAGE_RANGE) - min(VOLTAGE_RANGE))
    voltage = sorted([min_voltage, voltage, max_voltage])[1] - min_voltage
    return int(voltage/voltage_span*(2**DAC_BITS-1))

def ramp_rate(voltage_diff, ticks):
    v = voltage_to_signed(voltage_diff)
    t = ticks
    signed_ramp_rate = int(v*2.**int(np.log2(t)-1)/t)
    if signed_ramp_rate > 0:
        return signed_ramp_rate
    else:
        return signed_ramp_rate + 2**DAC_BITS

def make_sequence_bytes(ramps):
    # break into smaller pieces [(T, loc, {dt, dv})]
    unsorted_ramps = []
    for c in range(N_CHANNELS):
        T = 0
        V = 0
        for r in ramps[c]:
            r2 = {'dv': r['dv']}
            r2['dt'] = time_to_ticks(CLK, r['dt'])
            unsorted_ramps.append((T, c, r2))
            T += r2['dt']
            V += r2['dv']
        unsorted_ramps.append((T, c, {'dt': time_to_ticks(CLK, 0.1), 'dv': -V}))
        unsorted_ramps.append((T+100E-3, c, {'dt': time_to_ticks(CLK, 10), 'dv': 0}))

    # order ramps by when they happen, then physical location on board
    sorted_ramps = sorted(unsorted_ramps)

    # ints to bytes
    byte_array = []
    for r in sorted_ramps:
        byte_array += [int(eval(hex(ramp_rate(r[2]['dv'], r[2]['dt']))) 
                    >> i & 0xff) for i in range(0, 16, 8)]
        byte_array += [int(eval(hex(r[2]['dt'])) 
                    >> i & 0xff) for i in range(0, 32, 8)]
    
    # add dead space
    byte_array += [0]*24
    return byte_array

def set_mode(mode):
    mode_int = mode_ints[mode]
    fp.SetWireInValue(mode_wire, mode_int)
    sleep(0.1)
    fp.UpdateWireIns()
    sleep(0.1)

def program_sequence(sequence):
    byte_array = make_sequence_bytes(sequence)
    set_mode('idle')
    set_mode('load')
    fp.WriteToPipeIn(sequence_pipe, bytearray(byte_array))
    sleep(0.1)
    set_mode('idle')

def start_sequence():
    set_mode('run')

def setup_scope(scope):
    # Setup acquisition
    scope.write(":CHAN1:SCAL 0.5")
    scope.write(":CHAN1:OFFS 0")

    scope.write(":CHAN2:SCAL 5")
    scope.write(":CHAN2:OFFS 0")

    scope.write(":TIM:DEL:ENAB 0")
    scope.write(":TIM:OFFS 0.01")
    scope.write(":TIM:MODE MAIN")
    scope.write(":TIM:SCAL 0.005")

    scope.write(":ACQ:MDEP 100k")
    scope.write(":ACQ:TYPE HRES")

    scope.write(":WAV:SOUR CHAN1")
    scope.write(":WAV:MODE RAW")
    scope.write(":WAV:FORM ASC")
    scope.write(":WAV:POIN RAW")


    scope.write(":TRIG:MODE EDGE")
    scope.write(":TRIG:COUP DC")
    scope.write(":TRIG:SWE SING")
    scope.write(":TRIG:EDGE:SOUR CHAN2")
    scope.write(":TRIG:EDGE:SLOP POS")
    scope.write(":TRIG:EDGE:LEV 2.0")

    scope.write(":SOURCE:OUTPUT OFF")

    scope.write(":SYST:KEY:PRES MOFF")

    scope.flush(pyvisa.constants.VI_WRITE_BUF)

def acquire(scope):
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
    return (times, data)

if __name__ == "__main__":

    if len(sys.argv) < 2:
        raise(RuntimeError("Must specify filename as argument"))
    fname = str(sys.argv[1])

    rm = pyvisa.ResourceManager()
    resources = rm.list_resources()
    id = [i for i in resources if "MS5" in i]
    if len(id):
        scope = rm.open_resource(id[0])
    else:
        raise(RuntimeError("Could not connect to scope"))
        
    fp = ok.FrontPanel()
    device_count = fp.GetDeviceCount()
    print("{} devices connected".format(device_count))
    device_found = False
    for i in range(device_count):
        ser = fp.GetDeviceListSerial(i)
        fp.OpenBySerial(ser)
        id = fp.GetDeviceID()
        print("Checking {}".format(id))
        if "KRbAnlg06" in id:
            print("Connecting to {}".format(id))
            device_found = True
            break
    if device_found:
        fp.ConfigureFPGA(bitfile)
        print("Bitfile loaded!")

        def generate_ramps(c):
            ramps = []
            for _ in range(N_CHANNELS):
                ramps.append([{'dv':0.0, 'dt':10E-3},{'dv':1.0, 'dt':0.0001}, {'dv':0.0, 'dt':1.0}])
            return ramps

        n = N_CHANNELS
        data = np.empty((n, 6))
        for c in range(n):
            raw_input("Connect channel {} and press Enter to continue...".format(c))
            setup_scope(scope)
            print("Programming sequence")
            program_sequence(generate_ramps(1))
            sleep(1.0)
            print("Running sequence")
            start_sequence()
            x,y = acquire(scope)

            start_V = np.mean(y[:int(len(y)/3)])
            end_V = np.mean(y[-int(len(y)/3):])

            ten_percent = start_V + (end_V - start_V)/10.0
            fifty_percent = start_V + (end_V - start_V)/2.0
            ninety_percent = start_V + 9.0*(end_V - start_V)/10.0

            t10 = x[np.argmax(y > ten_percent)]
            t50 = x[np.argmax(y > fifty_percent)]
            t90 = x[np.argmax(y > ninety_percent)]

            maxv = np.max(y)

            stats = [start_V, maxv, end_V, t10, t50, t90]
            data[c,:] = stats
            print("start_V, maxv, end_V, t10, t50, t90")
            print(stats)

            # plt.plot(x,y)
            # plt.show()
        
        np.savetxt(fname, data, header="start_V maxv end_V t10 t50 t90")
        scope.close()
        fp.Close()

        print("Done acquiring!")
