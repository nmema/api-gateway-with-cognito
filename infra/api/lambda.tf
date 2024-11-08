data "archive_file" "lambda_connection" {
  type        = "zip"
  source_dir  = "${path.module}/../../backend/lambdas/connection"
  output_path = "${path.module}/lambda_connection.zip"
}

resource "aws_lambda_function" "lambda_connection" {
  function_name = "ConnectionFunction"
  filename      = data.archive_file.lambda_connection.output_path
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.12"
  role          = aws_iam_role.iam_for_lambda_apigw.arn

  source_code_hash = filebase64sha256(data.archive_file.lambda_connection.output_path)

}

data "archive_file" "lambda_custom" {
  type        = "zip"
  source_dir  = "${path.module}/../../backend/lambdas/custom"
  output_path = "${path.module}/lambda_custom.zip"
}

resource "aws_lambda_function" "lambda_custom" {
  function_name = "CustomFunction"
  filename      = data.archive_file.lambda_custom.output_path
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.12"
  role          = aws_iam_role.iam_for_lambda_apigw.arn

  environment {
    variables = {
      API_GATEWAY_ID = aws_apigatewayv2_api.api.id
      REGION         = var.aws_region
      STAGE          = aws_apigatewayv2_stage.stage.name
    }
  }

  source_code_hash = filebase64sha256(data.archive_file.lambda_custom.output_path)

}

resource "null_resource" "package_lambda_layer" {
  provisioner "local-exec" {
    command = <<EOT
      set -e # Exit immediately if a command exits with a non-zero status

      cd ${path.module}/../../backend/lambdas/authorizer

      python3 -m venv venv
      . venv/bin/activate
      mkdir -p python

      pip install -r requirements.txt -t python/
      zip -r ../../../infra/api/auth_layer.zip python/

      deactivate
      rm -rf venv python

    EOT
  }

  triggers = {
    requirements = filesha256("../../backend/lambdas/authorizer/requirements.txt")
  }
}

resource "aws_lambda_layer_version" "dependencies_layer" {
  filename            = "${path.module}/auth_layer.zip"
  layer_name          = "dependencies_layer"
  compatible_runtimes = ["python3.12"]
  source_code_hash    = filesha256("${path.module}/auth_layer.zip")

  depends_on = [null_resource.package_lambda_layer]

}

data "archive_file" "lambda_authorizer" {
  type        = "zip"
  source_dir  = "${path.module}/../../backend/lambdas/authorizer"
  output_path = "${path.module}/lambda_authorizer.zip"
}

resource "aws_lambda_function" "lambda_authorizer" {
  function_name = "AuthorizerFunction"
  filename      = data.archive_file.lambda_authorizer.output_path
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.12"
  role          = aws_iam_role.iam_for_lambda_apigw.arn

  layers = [aws_lambda_layer_version.dependencies_layer.arn]

  environment {
    variables = {
      COGNITO_USER_POOL_ID = data.terraform_remote_state.cognito.outputs.cognito_user_pool_id
      REGION               = var.aws_region
      CLIENT_ID            = data.terraform_remote_state.cognito.outputs.cognito_user_client_id
    }
  }

  source_code_hash = filebase64sha256(data.archive_file.lambda_authorizer.output_path)
}
