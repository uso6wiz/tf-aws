# tf-aws
Terraform for AWS

## セットアップ

### 前提条件

- AWS CLI がインストールされていること
- Terraform 1.6.0以上がインストールされていること

### AWS認証情報の設定

AWS CLIを使用して認証情報を設定します：

```bash
aws configure
```

以下の情報を入力します：
- AWS Access Key ID
- AWS Secret Access Key
- Default region name: `ap-southeast-1`
- Default output format: `json`（推奨）

### 実行手順

#### 1. バックエンドの作成（初回のみ）

Terraformの状態管理用のS3バケットとDynamoDBテーブルを作成します。

1. `state` ディレクトリに移動します：

```bash
cd state
```

2. Terraformを初期化します：

```bash
terraform init
```

3. 実行計画を確認します：

```bash
terraform plan
```

4. バックエンドリソースを作成します：

```bash
terraform apply
```

確認プロンプトで `yes` を入力して実行します。

これにより、以下のリソースが作成されます：
- S3バケット（Terraform状態ファイル用）
- DynamoDBテーブル（状態ロック用）

#### 2. サービスインフラの作成

バックエンド作成後、`service` ディレクトリでインフラを作成します。

1. `service` ディレクトリに移動します：

```bash
cd ../service
```

2. Terraformを初期化します：

```bash
terraform init
```

3. 実行計画を確認します：

```bash
terraform plan
```

必要に応じて変数を設定できます：

```bash
terraform plan -var="db_password=your_password" -var="ecs_container_image=your_image"
```

4. インフラを適用します：

```bash
terraform apply
```

確認プロンプトで `yes` を入力して実行します。

### 変数

主要な変数は `variables.tf` で定義されています。環境変数 `TF_VAR_*` または `-var` オプションで上書きできます。

例：
```bash
export TF_VAR_db_password="your_secure_password"
terraform apply
```

### 注意事項

- 本番環境では必ず `db_password` を上書きしてください（デフォルトは `password`）
- S3バックエンドのバケット名は実際の環境に合わせて変更してください（`main.tf` の `backend "s3"` セクション）
