program detect_jasco_error_state("SETPOINT,READBACK,STATUS,PUMPRUN,TIMERUN,PUMPSTOP,ERROR,TOLERANCE,DELAY,RESET")

/* The JASCO PU-4180 can enter a state where users will be unable to set components on the device. This state machine
   tries to detect when this issue occurs and restart the pump run (which retries setting the components). If the 
   components have not updated after a number of retries then the pump will be stopped and an error record will be 
   updated to warn the user. */

#include "seqPVmacros.h"
%% #include "errlog.h"
%% #include "math.h"

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
PV(int, pump_reset, "{RESET}", NoMon);

/* system pvs */
PV(double, tolerance, "{TOLERANCE}", Monitor);
PV(double, delay_time, "{DELAY}", Monitor);

double setpoint_old;
int retries = 0;
int retry_limit = 3;

%{
int notWithinTolerance(double setpoint, double readback, double tolerance) {
    return fabs(setpoint - readback) > tolerance;
}

}%

ss detect_jasco_error_state
{
    state check_mode
    {
        /* setpoint alarm must be zero to avoid sending zero to device when first starting driver (SP will be UDF_alarm) */
        when(notWithinTolerance(setpoint, readback, tolerance) && setpoint_alarm == 0 && status != 0)
        {
            setpoint_old = setpoint;
            errlogSevPrintf(errlogMinor, "detect_jasco_error_state: setpoint ('%s') not equal readback ('%s'). Resetting and reprocessing pump run in %f seconds if still not the same.\n", setpoint_description, readback_description, delay_time);
        } state checksp
        when(notWithinTolerance(setpoint, readback, tolerance) == FALSE && setpoint_alarm == 0 && status != 0 && retries != 0) 
        {
            errlogSevPrintf(errlogMinor, "detect_jasco_error_state: setpoint ('%s') equals readback ('%s'). Current retries ('%i') reset to 0.\n", setpoint_description, readback_description, retries);
            retries = 0;
            PVPUT(pump_error, 0);
        } state wait
    }

    state checksp
    {
         when(setpoint != setpoint_old)
         {
            errlogSevPrintf(errlogMinor, "detect_jasco_error_state: setpoint ('%s') changed - stopping check.\n", setpoint_description);
         } state wait

         when(delay(delay_time))
         {
            if (notWithinTolerance(setpoint, readback, tolerance) && setpoint_alarm == 0 && status != 0) {
                errlogSevPrintf(errlogMinor, "detect_jasco_error_state: setpoint ('%s') not equal readback ('%s'). Resetting and reprocessing pump run now, attempt ('%i')...\n", setpoint_description, readback_description, retries);
                PVPUT(pump_error, 1);
                if (retries > retry_limit) {
                    errlogSevPrintf(errlogMinor, "detect_jasco_error_state: Failed reprocessing setpoint ('%s') because maximum retries ('%i') exceeded. Stopping pump.\n", setpoint_description, retries);
                    PVPUT(pump_stop, 1);
                    retries = 0;
                } else {
                    retries += 1;
                    if (status == 1) {
                        errlogSevPrintf(errlogMinor, "Resetting pump");
                        PVPUT(pump_reset, 1);
                        epicsThreadSleep(1.0); /* or use SYNC on above? */
                        errlogSevPrintf(errlogMinor, "Restarting run");
                        PVPUT(pump_run, 1);
                    } else {
                        errlogSevPrintf(errlogMinor, "Resetting pump");
                        PVPUT(pump_reset, 1);
                        epicsThreadSleep(1.0); /* or use SYNC on above? */
                        errlogSevPrintf(errlogMinor, "Restarting run");
                        PVPUT(pump_timed, 1);
                    }
                }
            }
        } state wait
    }

    state wait
    {
      when(delay(delay_time))
      {
        ;
      } state check_mode
    }
}
