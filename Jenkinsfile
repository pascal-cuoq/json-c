pipeline {
  agent any
  parameters {
    choice(name: 'freq', choices: 'high', description: 'frequency')
    string(name: 'memory', defaultValue: '700M', description: '')
    string(name: 'timeout',  defaultValue: '6m', description: '')
    string(name: 'mailto',
           defaultValue: '',
           description: 'If not empty, send an mail to the user after the analysis completes. Suffix @trust-in-soft.com is automatically added.')
  }
  triggers {
    parameterizedCron('''
      H H(2-6) *    * * % freq=high; memory=700M; timeout=6m; mailto=anne.pacalet
        ''')
  }
  stages {
    stage('Run analysis') {
      steps {
        withCredentials([usernamePassword(\
              credentialsId: 'DOCKER_REGISTRY_IDS', \
              passwordVariable: 'DOCKER_REGISTRY_PASSWORD', \
              usernameVariable: 'DOCKER_REGISTRY_USERNAME')\
        ]) {
          sh """docker login \
                  --username=$DOCKER_REGISTRY_USERNAME \
                  --password=$DOCKER_REGISTRY_PASSWORD \
                  https://$DOCKER_REGISTRY \
             """
          sh """docker pull $DOCKER_REGISTRY/tis-analyzer:16.04"""
          sh """docker run \
                  --rm \
                  --security-opt seccomp=unconfined \
                  --memory=${params.memory} \
                  --volume $WORKSPACE:/scripts \
                  --workdir /scripts \
                  $DOCKER_REGISTRY/tis-analyzer:16.04 \
                  bash -c "source ~/.bashrc && \
                      echo -n GIT_COMMIT:tis-analyzer: && \
                      ( cat $DOCKER_JENKINS_HOME/installs/master/snapshot | \
                          grep -Po '[a-z0-9]* (?=utils/\$)' ) && \
                      tis_choose master && \
                      freq=${params.freq} timeout -k10s ${params.timeout} \
                      /scripts/tis/jenkins.sh -f -v -v" \
             """
        }
      }
    }
    stage('Test') {
      steps {
        script {
          results = junit testResults: 'tis/xunit.xml'
        }
      }
    }
  }
  post {
        always {
            sendChatNotif(colorFromStatus(), results)
        }

        unsuccessful {
            sendMailNotif(params.mailto, results)
        }
    }
}

String colorFromStatus() {
    switch (currentBuild.currentResult) {
        case "SUCCESS":
            return 'good'
            break
        case "UNSTABLE":
            return 'warning'
            break
        case "FAILURE":
            return 'danger'
            break
        case "ABORTED":
            return '#808080'
            break
        default:
            return '#EE82EE'
            break
    }
}

String prettyEnv() {
       return "freq=${params.freq}; memory=${params.memory}; timeout=${params.timeout}\n"
}


String prettyResults(results) {
    if (results != null) {
        def total = results.getTotalCount()
        def failed = results.getFailCount()
        def skipped = results.getSkipCount()
        def passed = total - failed - skipped
        message = "Passed: ${passed}; Failed: ${failed}; Skipped: ${skipped}\n"
        return message
    } else {
        return "NO TEST RESULTS AVAILABLE\n"
    }
}

void sendChatNotif(color, results) {
    def chat_message = "<${env.JOB_URL}/${env.BUILD_NUMBER}|${env.JOB_NAME} #${env.BUILD_NUMBER}>\n" +
        prettyEnv() +
        prettyResults(results) +
        "${currentBuild.currentResult} after ${currentBuild.durationString.replace(' and counting', '')} " +
        "(<${env.RUN_DISPLAY_URL}|See results>)"

    rocketSend attachments:
    [[$class: 'MessageAttachment',
      color: "$color",
      text: "$chat_message"]],
    channel: 'jenkins-analysis', rawMessage: true
}

void sendMailNotif(who, results) {
  if (who && who != "" ) {
    def mailto= "${who}@trust-in-soft.com"
    def msg = "${env.JOB_NAME} #${env.BUILD_NUMBER}: ${env.JOB_URL}${env.BUILD_NUMBER}\n" +
      prettyEnv() +
      prettyResults(results) +
      "${currentBuild.currentResult} after ${currentBuild.durationString.replace(' and counting', '')}\n" +
      "Results: ${env.RUN_DISPLAY_URL}"
    def title = "[jenkins] ${env.JOB_NAME} (${env.freq})" +
                " - ${currentBuild.currentResult}"
    emailext subject: "$title",
             to: "$mailto",
             replyTo: 'jenkins@trust-in-soft.com',
             body: "$msg"
  }
}
