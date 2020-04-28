s/\['high','medium','low']/'high'/

s/HIGH_MAINTAINER/anne.pacalet/
s/HIGH_MEM/700M/
s/HIGH_TIMEOUT/6m/

/\(MEDIUM\|LOW\)_MAINTAINER/d
/MEDIUM_TIMEOUT/d
/LOW_TIMEOUT/d

s=/scripts/jenkins.sh=/scripts/tis/jenkins.sh -f -v=
/junit testResults/s=xunit.xml=tis/xunit.xml=
