import * as cdk from 'aws-cdk-lib';
import * as iam from 'aws-cdk-lib/aws-iam';
import { Construct } from 'constructs';

export class AnthropicWIFStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    const accountId = cdk.Stack.of(this).account;

    const anthropicRole = new iam.Role(this, 'AnthropicWorkloadIdentity', {
      roleName: 'anthropic-workload-identity',
      assumedBy: new iam.AccountPrincipal(accountId),
      description:
        'Role for Anthropic WIF - allows AWS STS to generate JWT tokens for Anthropic API',
    });

    // Allow Bedrock Claude access (for Bedrock usage)
    anthropicRole.attachInlinePolicy(
      new iam.Policy(this, 'BedrockClaudeAccess', {
        statements: [
          new iam.PolicyStatement({
            effect: iam.Effect.ALLOW,
            actions: [
              'bedrock:InvokeModel',
              'bedrock:InvokeModelWithResponseStream',
            ],
            resources: [
              `arn:aws:bedrock:*:${accountId}:foundation-model/anthropic.claude-*`,
            ],
          }),
        ],
      })
    );

    // Allow minting the web identity JWT that Anthropic exchanges for an access token
    anthropicRole.attachInlinePolicy(
      new iam.Policy(this, 'WebIdentityTokenAccess', {
        statements: [
          new iam.PolicyStatement({
            effect: iam.Effect.ALLOW,
            actions: ['sts:GetWebIdentityToken'],
            resources: ['*'],
          }),
        ],
      })
    );

    new cdk.CfnOutput(this, 'RoleArn', {
      value: anthropicRole.roleArn,
      description: 'IAM Role ARN for Anthropic WIF (set AWS_ROLE_ARN to this)',
      exportName: 'AnthropicRoleArn',
    });

    new cdk.CfnOutput(this, 'RoleName', {
      value: anthropicRole.roleName,
      description: 'IAM Role Name',
      exportName: 'AnthropicRoleName',
    });

    new cdk.CfnOutput(this, 'AccountId', {
      value: accountId,
      description: 'AWS Account ID',
      exportName: 'AccountId',
    });
  }
}

const app = new cdk.App();
new AnthropicWIFStack(app, 'AnthropicWIFStack', {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION || 'us-east-1',
  },
});

app.synth();
