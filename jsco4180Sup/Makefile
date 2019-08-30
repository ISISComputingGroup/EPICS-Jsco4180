TOP=..
include $(TOP)/configure/CONFIG
#=======================================

# Install .dbd and .db files
DB += jsco4180.db
DATA += jsco4180.proto
DBD += detect_jasco_error_state.dbd

# Sequence file
LIBRARY_IOC = jsco4180
jsco4180_SRCS += detect_jasco_error_state.st
jsco4180_LIBS += seq pv
jsco4180_LIBS += $(EPICS_BASE_IOC_LIBS)

#=======================================
include $(TOP)/configure/RULES
