program detect_jasco_error_state("SETPOINT,READBACK,STATUS,PUMPRUN,TIMERUN,PUMPSTOP,MODE,ERROR,TOLERANCE,DELAY")

/* The JASCO PU-4180 can enter a state where users will be unable to set components on the device. This state machine
   tries to detect when this issue occurs and restart the pump run. If the components have not updated after a number
   of retries then the pump will be stopped and an error record will be updated to warn the user. */

#include "seqPVmacros.h"
%% #include "errlog.h"

/* Turn on run-time debug messages */
option +d;

/* Make code reentrant. This is needed to run more than one instance of this program. */
option +r;

/* Setpoint-related PVs */
PV(double, setpoint, "{SETPOINT}", Monitor);
PV(int, setpoint_proc, "{SETPOINT}.PROC", NoMon);
PV(int, setpoint_alarm, "{SETPOINT}.SEVR", Monitor);
PV(string, setpoint_description, "{SETPOINT}.DESC", Monitor);

/* Readback-related PVs */
PV(string, readback_description, "{READBACK}.DESC", Monitor);
PV(double, readback, "{READBACK}", Monitor);

/* STATUS-related PVs */
PV(int, status, "{STATUS}", Monitor);

/* Pump Control related PVs */
PV(int, pump_run, "{PUMPRUN}", NoMon);
PV(int, pump_timed, "{TIMERUN}", NoMon);
PV(int, pump_stop, "{PUMPSTOP}", NoMon);
PV(int, pump_error, "{ERROR}", NoMon);
PV(int, pump_mode, "{MODE}", Monitor);

/* system pvs */
PV(double, tolerance, "{TOLERANCE}", Monitor);
PV(double, delay, "{DELAY}", Monitor); 

int retries = 0;

%{
int notWithinTolerance(double setpoint, double readback, double tolerance) {
    return fabs(setpoint - readback) > tolerance;
}

}%

ss detect_jasco_error_state
{
    /* Initial state. */
    state idle
    {
        /* setpoint alarm must be zero to avoid sending zero to device when first starting driver (SP will be UDF_alarm) */
        when(notWithinTolerance(setpoint, readback, tolerance) && setpoint_alarm == 0 && status == 1) 
        {
            errlogSevPrintf(errlogMinor, "detect_jasco_error_state: setpoint ('%s') not equal readback ('%s'). Reprocessing pump run in %f seconds if still not the same.\n", setpoint_description, readback_description, delay);

            epicsThreadSleep(delay);

            if (notWithinTolerance(setpoint, readback, tolerance) && setpoint_alarm == 0 && status == 1 ) {
                errlogSevPrintf(errlogMinor, "detect_jasco_error_state: setpoint ('%s') not equal readback ('%s'). Reprocessing pump run now, attempt ('%i')...\n", setpoint_description, readback_description, retries);
                if (retries > 3) {
                    errlogSevPrintf(errlogMinor, "detect_jasco_error_state: Not reprocessing setpoint ('%s') because maximum retries ('%i') exceeded. Stopping pump.\n", setpoint_description, retries);
                    PVPUT(pump_stop, 1)
                    PVPUT(pump_error, 1)
                } else {
                    retries += 1;
                    if (pump_mode == 1) {
                        PVPUT(pump_run, 1);
                    } else if (pump_mode == 2) {
                        PVPUT(pump_timed, 1)
                    }
                }
            } else {
                errlogSevPrintf(errlogMinor, "detect_jasco_error_state: setpoint ('%s') equal readback ('%s'). \n", setpoint_description, readback_description, retries);
                PVPUT(pump_error, 0)
            }
        } state wait
        when(notWithinTolerance(setpoint, readback, tolerance) == FALSE && setpoint_alarm == 0 && status == 1 && retries != 0) 
        {
            errlogSevPrintf(errlogMinor, "detect_jasco_error_state: setpoint ('%s') equal readback ('%s'). Current retries ('%i') reset to 0.\n", setpoint_description, readback_description, retries);
            retries = 0;
            PVPUT(pump_error, 0)
        } state idle
    }

    state wait
    {
      when(1)
      {
        epicsThreadSleep(delay);
      } state idle
    }
}
