// Existing Terraform src code found at /tmp/terraform_src.

locals {
  stack_id = uuidv5("dns", "AzurePipelinesAgents")
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_partition" "current" {}

variable azure_dev_ops_agent_url_parameter_name {
  description = "(Required) The name of the String Systems Manager Parameter that contains the URL to download the Azure DevOps Build Agent."
  type = string
}

variable azure_dev_ops_pat_parameter_name {
  description = "(Required) The name of the SecureString Systems Manager Parameter that contains the Azure DevOps Agent personal access token (PAT)."
  type = string
}

variable azure_dev_ops_agent_pool_name {
  description = "(Required) pool name for the Azure DevOps Pipelines agents to join."
  type = string
}

variable azure_dev_ops_organization_url {
  description = "(Required) URL of the server. For example: https://dev.azure.com/myorganization or https://my-azure-devops-server/tfs."
  type = string
}

variable ami_id_parameter_name {
  description = "Region specific image from the Parameter Store"
  type = string
  default = "/aws/service/ami-windows-latest/Windows_Server-2022-English-Full-Base"
}

variable instance_type {
  description = "Amazon EC2 instance type for the instances"
  type = string
  default = "t3.medium"
}

variable subnets {
  description = "A list of subnets for the Auto Scaling group"
  type = string
}

variable security_group {
  description = "List of Security Groups to add to EC2 instance"
  type = string
}

variable schedule_scale_out_cron {
  description = "The cron expression to use for the scheduled scaling out event in UTC. For more information about this format, see http://crontab.org/."
  type = string
  default = "0 7 * * *"
}

variable scale_out_max_capacity {
  description = "The auto scaling Max Size when scale out."
  type = string
}

variable scale_out_min_capacity {
  description = "The auto scaling Min Size when scale out."
  type = string
}

variable scale_out_desired_capacity {
  description = "The auto scaling Desired Capacity when scale out."
  type = string
}

variable schedule_scale_in_cron {
  description = "The cron expression to use for the scheduled scale in event in UTC. For more information about this format, see http://crontab.org/."
  type = string
  default = "0 19 * * *"
}

variable scale_in_max_capacity {
  description = "The auto scaling Max Size when scale in."
  type = string
}

variable scale_in_min_capacity {
  description = "The auto scaling Min Size when scale in."
  type = string
}

variable scale_in_desired_capacity {
  description = "The auto scaling Desired Capacity when scale in."
  type = string
}

resource "aws_iam_role" "event_bridge_rule_role" {
  assume_role_policy = {
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = [
            "events.amazonaws.com"
          ]
        }
        Action = [
          "sts:AssumeRole"
        ]
      }
    ]
  }
  force_detach_policies = [
    {
      PolicyDocument = {
        Version = "2012-10-17"
        Statement = [
          {
            Effect = "Allow"
            Action = [
              "ssm:StartAutomationExecution"
            ]
            Resource = [
              "arn:${data.aws_partition.current.partition}:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:automation-definition/${aws_ssm_document.azure_pipeline_scale_out.created_date}:$DEFAULT",
              "arn:${data.aws_partition.current.partition}:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:automation-definition/${aws_ssm_document.azure_pipeline_scale_in.created_date}:$DEFAULT"
            ]
          }
        ]
      }
      PolicyName = "Start-SSM-Automation-Policy"
    },
    {
      PolicyDocument = {
        Version = "2012-10-17"
        Statement = [
          {
            Effect = "Allow"
            Action = [
              "iam:PassRole"
            ]
            Resource = aws_iam_role.aws_systems_manager_automation_role.arn
          }
        ]
      }
      PolicyName = "Pass-Role-SSM-Automation-Policy"
    }
  ]
  tags = {
    CloudFormation StackId = local.stack_id
  }
}

resource "aws_iam_role" "aws_systems_manager_automation_role" {
  assume_role_policy = {
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = [
            "ssm.amazonaws.com"
          ]
        }
        Action = [
          "sts:AssumeRole"
        ]
      }
    ]
  }
  force_detach_policies = [
    {
      PolicyDocument = {
        Version = "2012-10-17"
        Statement = [
          {
            Effect = "Allow"
            Action = [
              "ssm:DescribeInstanceInformation",
              "ssm:ListCommands",
              "ssm:ListCommandInvocations"
            ]
            Resource = "*"
          },
          {
            Effect = "Allow"
            Action = [
              "ssm:SendCommand"
            ]
            Resource = [
              "arn:${data.aws_partition.current.partition}:ssm:${data.aws_region.current.name}::document/AWS-RunPowerShellScript",
              "arn:${data.aws_partition.current.partition}:ssm:${data.aws_region.current.name}::document/AWS-RunShellScript"
            ]
          },
          {
            Action = [
              "ssm:SendCommand"
            ]
            Resource = "arn:${data.aws_partition.current.partition}:ec2:*:*:instance/*"
            Effect = "Allow"
          }
        ]
      }
      PolicyName = "SSM-Automation-Policy"
    },
    {
      PolicyDocument = {
        Version = "2012-10-17"
        Statement = [
          {
            Effect = "Allow"
            Action = [
              "autoscaling:CompleteLifecycleAction"
            ]
            Resource = "arn:${data.aws_partition.current.partition}:autoscaling:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:autoScalingGroup:*:autoScalingGroupName/${aws_autoscalingplans_scaling_plan.azure_dev_ops_agent_pool_asg.id}"
          }
        ]
      }
      PolicyName = "SSM-Automation-Permission-to-CompleteLifecycle-Policy"
    }
  ]
  tags = {
    CloudFormation StackId = local.stack_id
  }
}

resource "aws_iam_role" "ssm_instance_profile_role" {
  assume_role_policy = {
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = [
            "ec2.amazonaws.com"
          ]
        }
        Action = [
          "sts:AssumeRole"
        ]
      }
    ]
  }
  managed_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  ]
  tags = {
    CloudFormation StackId = local.stack_id
  }
}

resource "aws_iam_instance_profile" "ssm_instance_profile" {
  role = [
    aws_iam_role.ssm_instance_profile_role.arn
  ]
}

resource "aws_launch_template" "azure_dev_ops_agent_pool_asg_launch_template" {
  user_data = {
    ImageId = var.ami_id_parameter_name
    InstanceType = var.instance_type
    IamInstanceProfile = {
      Arn = aws_iam_instance_profile.ssm_instance_profile.arn
    }
    SecurityGroupIds = var.security_group
    EbsOptimized = True
    BlockDeviceMappings = [
      {
        Ebs = {
          VolumeSize = 50
          VolumeType = "gp3"
          DeleteOnTermination = True
        }
        DeviceName = "/dev/sda1"
      }
    ]
    TagSpecifications = [
      {
        ResourceType = "instance"
        Tags = [
          {
            Key = "Name"
            Value = var.azure_dev_ops_agent_pool_name
          }
        ]
      }
    ]
  }
}

resource "aws_autoscalingplans_scaling_plan" "azure_dev_ops_agent_pool_asg" {
  // CF Property(LaunchTemplate) = {
  //   LaunchTemplateId = aws_launch_template.azure_dev_ops_agent_pool_asg_launch_template.arn
  //   Version = aws_launch_template.azure_dev_ops_agent_pool_asg_launch_template.latest_version
  // }
  max_capacity = var.scale_in_max_capacity
  min_capacity = "0"
  predictive_scaling_max_capacity_behavior = "0"
  // CF Property(VPCZoneIdentifier) = var.subnets
  // CF Property(LifecycleHookSpecificationList) = [
  //   {
  //     LifecycleHookName = "LifeCycleHookScaleIn"
  //     LifecycleTransition = "autoscaling:EC2_INSTANCE_TERMINATING"
  //     DefaultResult = "ABANDON"
  //   },
  //   {
  //     LifecycleHookName = "LifeCycleHookScaleOut"
  //     LifecycleTransition = "autoscaling:EC2_INSTANCE_LAUNCHING"
  //     DefaultResult = "ABANDON"
  //   }
  // ]
}

resource "aws_ssm_document" "azure_pipeline_scale_in" {
  document_type = "Automation"
  content = {
    schemaVersion = "0.3"
    assumeRole = "{{AutomationAssumeRole}}"
    description = "This Document Created as part of CloudFormation stack. This document will remove the Azure Pipelines agent from the agent pool. Then it will send a signal to the LifeCycleHook to terminate the instance"
    parameters = {
      InstanceId = {
        type = "String"
      }
      ASGName = {
        type = "String"
        default = aws_autoscalingplans_scaling_plan.azure_dev_ops_agent_pool_asg.id
        description = "The name of the Auto Scaling Group."
      }
      LCHName = {
        type = "String"
        default = "LifeCycleHookScaleIn"
        description = "The name of the Life Cycle Hook."
      }
      AgentToken = {
        type = "String"
        default = var.azure_dev_ops_pat_parameter_name
        description = "The name of the Secure Parameter that contains the Azure DevOps personal access token (PAT)"
      }
      AutomationAssumeRole = {
        type = "String"
        default = aws_iam_role.aws_systems_manager_automation_role.arn
        description = "(Required) The ARN of the role that allows Automation to perform the actions on your behalf."
      }
    }
    mainSteps = [
      {
        name = "verifyInstancesOnlineSSM"
        action = "aws:waitForAwsResourceProperty"
        timeoutSeconds = 600
        onFailure = "Continue"
        inputs = {
          Service = "ssm"
          Api = "DescribeInstanceInformation"
          InstanceInformationFilterList = [
            {
              key = "InstanceIds"
              valueSet = [
                "{{ InstanceId }}"
              ]
            }
          ]
          PropertySelector = "$.InstanceInformationList[0].PingStatus"
          DesiredValues = [
            "Online"
          ]
        }
        nextStep = "GetInstance"
      },
      {
        name = "GetInstance"
        action = "aws:executeAwsApi"
        maxAttempts = 15
        onFailure = "Continue"
        inputs = {
          Service = "ssm"
          Api = "DescribeInstanceInformation"
          Filters = [
            {
              Key = "InstanceIds"
              Values = [
                "{{ InstanceId }}"
              ]
            }
          ]
        }
        outputs = [
          {
            Name = "myInstance"
            Selector = "$.InstanceInformationList[0].InstanceId"
            Type = "String"
          },
          {
            Name = "platform"
            Selector = "$.InstanceInformationList[0].PlatformType"
            Type = "String"
          }
        ]
      },
      {
        name = "ChooseOSforCommands"
        action = "aws:branch"
        inputs = {
          Choices = [
            {
              NextStep = "runPowerShellCommand"
              Variable = "{{GetInstance.platform}}"
              StringEquals = "Windows"
            },
            {
              NextStep = "runShellCommand"
              Variable = "{{GetInstance.platform}}"
              StringEquals = "Linux"
            }
          ]
          Default = "ContinueLifecycleAction"
        }
      },
      {
        name = "runPowerShellCommand"
        action = "aws:runCommand"
        nextStep = "ContinueLifecycleAction"
        onFailure = "step:ContinueLifecycleAction"
        inputs = {
          DocumentName = "AWS-RunPowerShellScript"
          InstanceIds = [
            "{{ InstanceId }}"
          ]
          Parameters = {
            executionTimeout = "7200"
            commands = "$ErrorActionPreference="Stop"
If(-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent() ).IsInRole( [Security.Principal.WindowsBuiltInRole] "Administrator")){ throw "Run command in an administrator PowerShell prompt"}
If($PSVersionTable.PSVersion -lt (New-Object System.Version("3.0"))){ throw "The minimum version of Windows PowerShell that is required by the script (3.0) does not match the currently running version of Windows PowerShell." }
If(-NOT (Test-Path $env:SystemDrive\'azagent')){mkdir $env:SystemDrive\'azagent'}
cd $env:SystemDrive\'azagent';
$DefaultProxy=[System.Net.WebRequest]::DefaultWebProxy
$securityProtocol=@()
$securityProtocol+=[Net.ServicePointManager]::SecurityProtocol
$securityProtocol+=[Net.SecurityProtocolType]::Tls12
[Net.ServicePointManager]::SecurityProtocol=$securityProtocol
$token = (Get-SSMParameterValue -Name {{ AgentToken }} -WithDecryption $True).Parameters[0].Value
.\config.cmd remove --unattended --auth PAT --token $token"
          }
        }
      },
      {
        name = "runShellCommand"
        action = "aws:runCommand"
        nextStep = "ContinueLifecycleAction"
        onFailure = "step:ContinueLifecycleAction"
        inputs = {
          DocumentName = "AWS-RunShellScript"
          InstanceIds = [
            "{{ InstanceId }}"
          ]
          Parameters = {
            executionTimeout = "7200"
            commands = "#remove
cd /opt/azagent
./svc.sh stop
./svc.sh uninstall
export AGENT_ALLOW_RUNASROOT="1"
token=$(aws ssm get-parameter --name {{ AgentToken }} --with-decryption --query "Parameter.Value" --output text)
./config.sh remove --unattended --auth PAT --token $token"
          }
        }
      },
      {
        name = "ContinueLifecycleAction"
        action = "aws:executeAwsApi"
        maxAttempts = 15
        inputs = {
          Service = "autoscaling"
          Api = "CompleteLifecycleAction"
          AutoScalingGroupName = "{{ ASGName }}"
          InstanceId = "{{ InstanceId }}"
          LifecycleActionResult = "CONTINUE"
          LifecycleHookName = "{{ LCHName }}"
        }
      }
    ]
  }
}

resource "aws_ssm_document" "azure_pipeline_scale_out" {
  document_type = "Automation"
  content = {
    schemaVersion = "0.3"
    assumeRole = "{{AutomationAssumeRole}}"
    description = "This Document Created as part of CloudFormation stack. This document install the Azure Pipelines agent software on the instance, send a signal to the LifeCycleHook to put the instance InService"
    parameters = {
      InstanceId = {
        type = "String"
      }
      ASGName = {
        type = "String"
        default = aws_autoscalingplans_scaling_plan.azure_dev_ops_agent_pool_asg.id
        description = "The name of the Auto Scaling Group."
      }
      LCHName = {
        type = "String"
        default = "LifeCycleHookScaleOut"
        description = "The name of the Life Cycle Hook."
      }
      AgentURL = {
        type = "String"
        default = var.azure_dev_ops_agent_url_parameter_name
        description = "The SSM Parameter containing the URL to download the Azure DevOps Agent"
      }
      AgentToken = {
        type = "String"
        default = var.azure_dev_ops_pat_parameter_name
        description = "The name of the SecureString Parameter that contains the Personal Access Token (PAT) of DomainUserName"
      }
      AgentPool = {
        type = "String"
        default = var.azure_dev_ops_agent_pool_name
        description = "The name of the SecureString Parameter that contains the Agent Pool Name of DomainUserName"
      }
      OrganizationURL = {
        type = "String"
        default = var.azure_dev_ops_organization_url
        description = "URL of the server. For example: https://dev.azure.com/myorganization or http://my-azure-devops-server:8080/tfs"
      }
      AutomationAssumeRole = {
        type = "String"
        default = aws_iam_role.aws_systems_manager_automation_role.arn
        description = "(Required) The ARN of the role that allows Automation to perform the actions on your behalf."
      }
    }
    mainSteps = [
      {
        name = "verifyInstancesOnlineSSM"
        action = "aws:waitForAwsResourceProperty"
        timeoutSeconds = 600
        onFailure = "step:AbandonLifecycleAction"
        inputs = {
          Service = "ssm"
          Api = "DescribeInstanceInformation"
          InstanceInformationFilterList = [
            {
              key = "InstanceIds"
              valueSet = [
                "{{ InstanceId }}"
              ]
            }
          ]
          PropertySelector = "$.InstanceInformationList[0].PingStatus"
          DesiredValues = [
            "Online"
          ]
        }
        nextStep = "GetInstance"
      },
      {
        name = "GetInstance"
        action = "aws:executeAwsApi"
        maxAttempts = 15
        onFailure = "step:AbandonLifecycleAction"
        inputs = {
          Service = "ssm"
          Api = "DescribeInstanceInformation"
          Filters = [
            {
              Key = "InstanceIds"
              Values = [
                "{{ InstanceId }}"
              ]
            }
          ]
        }
        outputs = [
          {
            Name = "myInstance"
            Selector = "$.InstanceInformationList[0].InstanceId"
            Type = "String"
          },
          {
            Name = "platform"
            Selector = "$.InstanceInformationList[0].PlatformType"
            Type = "String"
          }
        ]
      },
      {
        name = "ChooseOSforCommands"
        action = "aws:branch"
        inputs = {
          Choices = [
            {
              NextStep = "runPowerShellCommand"
              Variable = "{{GetInstance.platform}}"
              StringEquals = "Windows"
            },
            {
              NextStep = "runShellCommand"
              Variable = "{{GetInstance.platform}}"
              StringEquals = "Linux"
            }
          ]
          Default = "AbandonLifecycleAction"
        }
      },
      {
        name = "runPowerShellCommand"
        action = "aws:runCommand"
        nextStep = "ContinueLifecycleAction"
        onFailure = "step:AbandonLifecycleAction"
        inputs = {
          DocumentName = "AWS-RunPowerShellScript"
          InstanceIds = [
            "{{ InstanceId }}"
          ]
          Parameters = {
            executionTimeout = "7200"
            commands = "$ErrorActionPreference="Stop"
If(-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent() ).IsInRole( [Security.Principal.WindowsBuiltInRole] "Administrator")){ throw "Run command in an administrator PowerShell prompt"}
If($PSVersionTable.PSVersion -lt (New-Object System.Version("3.0"))){ throw "The minimum version of Windows PowerShell that is required by the script (3.0) does not match the currently running version of Windows PowerShell." }
If(-NOT (Test-Path $env:SystemDrive\'azagent')){mkdir $env:SystemDrive\'azagent'}
cd $env:SystemDrive\'azagent';
#for($i=1; $i -lt 100; $i++){$destFolder="A"+$i.ToString()
#if(-NOT (Test-Path ($destFolder))){mkdir $destFolder;cd $destFolder;break;}}
$agentZip="$PWD\agent.zip";$DefaultProxy=[System.Net.WebRequest]::DefaultWebProxy
$securityProtocol=@()
$securityProtocol+=[Net.ServicePointManager]::SecurityProtocol
$securityProtocol+=[Net.SecurityProtocolType]::Tls12
[Net.ServicePointManager]::SecurityProtocol=$securityProtocol
$WebClient=New-Object Net.WebClient
$Uri = (Get-SSMParameterValue -Name {{ AgentURL }}).Parameters[0].Value
if($DefaultProxy -and (-not $DefaultProxy.IsBypassed($Uri))){$WebClient.Proxy= New-Object Net.WebProxy($DefaultProxy.GetProxy($Uri).OriginalString, $True);}
$WebClient.DownloadFile($Uri, $agentZip)
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::ExtractToDirectory( $agentZip, "$PWD")
$token = (Get-SSMParameterValue -Name {{ AgentToken }} -WithDecryption $True).Parameters[0].Value
.\config.cmd --unattended --pool {{ AgentPool }} --agent $env:COMPUTERNAME --runAsService --windowsLogonAccount "NT AUTHORITY\SYSTEM" --work '_work' --url {{ OrganizationURL }} --auth PAT --token $token
Remove-Item $agentZip

# You can remove the remaing line of code if you do not want the Git client automatically installed
Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
C:\ProgramData\chocolatey\bin\choco install git.install -y -f  -Wait

# You can remove the remaing line of code if you do not want the Visual Studio Build tools automatically installed.
$vs_buildtools="$PWD\vs_buildtools.exe";
wget https://aka.ms/vs/17/release/vs_buildtools.exe -UseBasicParsing -outfile $vs_buildtools
& $vs_buildtools --quiet --allWorkloads --includeOptional"
          }
        }
      },
      {
        name = "runShellCommand"
        action = "aws:runCommand"
        nextStep = "ContinueLifecycleAction"
        onFailure = "step:AbandonLifecycleAction"
        inputs = {
          DocumentName = "AWS-RunShellScript"
          InstanceIds = [
            "{{ InstanceId }}"
          ]
          Parameters = {
            executionTimeout = "7200"
            commands = "#Add an initial pause to let yum finish initializing
sleep 1m;
#install Prerequisities
yum install dotnet-sdk-6.0 -y;
#install agent
mkdir /opt/azagent;
chown ec2-user /opt/azagent;
cd /opt/azagent;
Uri=$(aws ssm get-parameter --name {{ AgentURL }} --query "Parameter.Value" --output text);
sudo -u ec2-user wget -q $Uri -O az_agent.tar.gz || exit 22;
sudo -u ec2-user tar zvxf az_agent.tar.gz || exit 22;
token=$(aws ssm get-parameter --name {{ AgentToken }} --with-decryption --query "Parameter.Value" --output text);
sudo -i -u ec2-user /opt/azagent/env.sh;
sudo -i -u ec2-user /opt/azagent/config.sh --unattended --url {{ OrganizationURL }} --auth pat --token $token --pool {{ AgentPool }} || exit 22;
/opt/azagent/svc.sh install ec2-user;
/opt/azagent/svc.sh start;
yum install git -y;"
          }
        }
      },
      {
        name = "ContinueLifecycleAction"
        action = "aws:executeAwsApi"
        maxAttempts = 15
        isEnd = True
        inputs = {
          Service = "autoscaling"
          Api = "CompleteLifecycleAction"
          AutoScalingGroupName = "{{ ASGName }}"
          InstanceId = "{{ InstanceId }}"
          LifecycleActionResult = "CONTINUE"
          LifecycleHookName = "{{ LCHName }}"
        }
      },
      {
        name = "AbandonLifecycleAction"
        action = "aws:executeAwsApi"
        maxAttempts = 15
        isEnd = True
        inputs = {
          Service = "autoscaling"
          Api = "CompleteLifecycleAction"
          AutoScalingGroupName = "{{ ASGName }}"
          InstanceId = "{{ InstanceId }}"
          LifecycleActionResult = "ABANDON"
          LifecycleHookName = "{{ LCHName }}"
        }
      }
    ]
  }
}

resource "aws_cloudwatch_event_rule" "event_bridge_rule_scale_in" {
  description = "Amazon EventBridge rule that will trigger AWS Systems Manager Automation document when an instance go in Terminate:wait. This is created as a part of a CloudFormation."
  event_pattern = {
    source = [
      "aws.autoscaling"
    ]
    detail-type = [
      "EC2 Instance-terminate Lifecycle Action"
    ]
    detail = {
      AutoScalingGroupName = [
        aws_autoscalingplans_scaling_plan.azure_dev_ops_agent_pool_asg.id
      ]
    }
  }
  // CF Property(Targets) = [
  //   {
  //     Arn = "arn:${data.aws_partition.current.partition}:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:automation-definition/${aws_ssm_document.azure_pipeline_scale_in.created_date}:$DEFAULT"
  //     RoleArn = aws_iam_role.event_bridge_rule_role.arn
  //     Id = "TargetFunctionV1"
  //     InputTransformer = {
  //       InputPathsMap = {
  //         instanceid = "$.detail.EC2InstanceId"
  //       }
  //       InputTemplate = join("", ["{"InstanceId":[<instanceid>]}"])
  //     }
  //   }
  // ]
}

resource "aws_cloudwatch_event_rule" "event_bridge_rule_scale_out" {
  description = "Amazon EventBridge rule that will trigger AWS Systems Manager Automation document when an instance go in Pending:Wait. This is created as a part of a CloudFormation."
  event_pattern = {
    source = [
      "aws.autoscaling"
    ]
    detail-type = [
      "EC2 Instance-launch Lifecycle Action"
    ]
    detail = {
      AutoScalingGroupName = [
        aws_autoscalingplans_scaling_plan.azure_dev_ops_agent_pool_asg.id
      ]
    }
  }
  // CF Property(Targets) = [
  //   {
  //     Arn = "arn:${data.aws_partition.current.partition}:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:automation-definition/${aws_ssm_document.azure_pipeline_scale_out.created_date}:$DEFAULT"
  //     RoleArn = aws_iam_role.event_bridge_rule_role.arn
  //     Id = "TargetFunctionV1"
  //     InputTransformer = {
  //       InputPathsMap = {
  //         instanceid = "$.detail.EC2InstanceId"
  //       }
  //       InputTemplate = join("", ["{"InstanceId":[<instanceid>]}"])
  //     }
  //   }
  // ]
}

resource "aws_appautoscaling_scheduled_action" "scheduled_action_out" {
  name = aws_autoscalingplans_scaling_plan.azure_dev_ops_agent_pool_asg.id
  // CF Property(MaxSize) = var.scale_out_max_capacity
  // CF Property(MinSize) = var.scale_out_min_capacity
  // CF Property(DesiredCapacity) = var.scale_out_desired_capacity
  // CF Property(Recurrence) = var.schedule_scale_out_cron
}

resource "aws_appautoscaling_scheduled_action" "scheduled_action_in" {
  name = aws_autoscalingplans_scaling_plan.azure_dev_ops_agent_pool_asg.id
  // CF Property(MaxSize) = var.scale_in_max_capacity
  // CF Property(MinSize) = var.scale_in_min_capacity
  // CF Property(DesiredCapacity) = var.scale_in_desired_capacity
  // CF Property(Recurrence) = var.schedule_scale_in_cron
}

output "auto_scaling_group" {
  description = "The name to the Auto Scaling group."
  value = aws_autoscalingplans_scaling_plan.azure_dev_ops_agent_pool_asg.id
}

output "instance_profile_name" {
  description = "The name to the IAM instance profile."
  value = aws_iam_instance_profile.ssm_instance_profile.arn
}
