#!/bin/bash

#echo "Sending data to RSPAMD_HOST"
exec /usr/bin/rspamc -h RSPAMD_HOST learn_ham
