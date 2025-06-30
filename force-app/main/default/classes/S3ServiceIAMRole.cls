public class S3ServiceIAMRole {

    private String accessKey;
    private String secretKey;
    private String sessionToken;
    private String bucketName;
    private String region;
    private String service = 's3';

    public S3ServiceIAMRole() {
        AWS_Configuration__mdt config = [
            SELECT AWS_Access_Key__c, AWS_Secret_Key__c, S3_Bucket_Name__c, AWS_Region__c, IAM_Role_ARN__c
            FROM AWS_Configuration__mdt
            WHERE DeveloperName = 'Default_S3_Config'
            LIMIT 1
        ];

        if (config == null) {
            throw new CalloutException('Could not find Custom Metadata record named Default_S3_Config.');
        }

        String permanentAccessKey = config.AWS_Access_Key__c;
        String permanentSecretKey = config.AWS_Secret_Key__c;
        String roleArn = config.IAM_Role_ARN__c;
        this.bucketName = config.S3_Bucket_Name__c;
        this.region = config.AWS_Region__c;

        assumeRole(permanentAccessKey, permanentSecretKey, roleArn);
    }

    private void assumeRole(String userKey, String userSecret, String roleArn) {
        HttpRequest req = new HttpRequest();
        req.setMethod('POST');
        req.setEndpoint('https://sts.amazonaws.com');
        req.setHeader('Content-Type', 'application/x-www-form-urlencoded');

        String requestBody = 'Action=AssumeRole' +
            '&RoleArn=' + EncodingUtil.urlEncode(roleArn, 'UTF-8') +
            '&RoleSessionName=SalesforceS3Upload' +
            '&Version=2011-06-15';
        req.setBody(requestBody);
        
        // Using the dynamic region from your config
        signRequest(req, userKey, userSecret, this.region, 'sts');

        Http http = new Http();
        HttpResponse res = http.send(req);

        if (res.getStatusCode() == 200) {
            Dom.Document doc = res.getBodyDocument();
            Dom.XMLNode root = doc.getRootElement();
            
            // **CRITICAL FIX:** Define and use the AWS STS XML Namespace
            String stsNamespace = 'https://sts.amazonaws.com/doc/2011-06-15/';
            
            Dom.XMLNode resultNode = root.getChildElement('AssumeRoleResult', stsNamespace);
            if (resultNode != null) {
                Dom.XMLNode credsNode = resultNode.getChildElement('Credentials', stsNamespace);
                if(credsNode != null) {
                    this.accessKey = credsNode.getChildElement('AccessKeyId', stsNamespace).getText();
                    this.secretKey = credsNode.getChildElement('SecretAccessKey', stsNamespace).getText();
                    this.sessionToken = credsNode.getChildElement('SessionToken', stsNamespace).getText();
                } else {
                     throw new CalloutException('Credentials node not found in STS response.');
                }
            } else {
                throw new CalloutException('AssumeRoleResult node not found in STS response.');
            }
        } else {
            throw new CalloutException('AWS STS AssumeRole call failed: ' + res.getBody());
        }
    }
    
    // The rest of the class is correct and unchanged
    private void signRequest(HttpRequest req, String key, String secret, String awsRegion, String awsService) {
        Datetime dt = Datetime.now();
        String iso8601Date = dt.formatGmt('yyyyMMdd');
        String iso8601Time = dt.formatGmt('yyyyMMdd\'T\'HHmmss\'Z\'');
        
        String host = req.getEndpoint().removeStart('https://');
        String canonicalHeaders = 'content-type:' + req.getHeader('Content-Type') + '\nhost:' + host + '\nx-amz-date:' + iso8601Time + '\n';
        String signedHeaders = 'content-type;host;x-amz-date';
        String payloadHash = EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', Blob.valueOf(req.getBody() != null ? req.getBody() : '')));
        
        String canonicalRequest = req.getMethod() + '\n/\n\n' + canonicalHeaders + '\n' + signedHeaders + '\n' + payloadHash;
        String credentialScope = iso8601Date + '/' + awsRegion + '/' + awsService + '/aws4_request';
        String stringToSign = 'AWS4-HMAC-SHA256\n' + iso8601Time + '\n' + credentialScope + '\n' + EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', Blob.valueOf(canonicalRequest)));

        Blob signingKey = getSigningKey(secret, iso8601Date, awsRegion, awsService);
        Blob signature = Crypto.generateMac('hmacSHA256', Blob.valueOf(stringToSign), signingKey);
        
        String authHeader = 'AWS4-HMAC-SHA256 Credential=' + key + '/' + credentialScope +
                            ', SignedHeaders=' + signedHeaders + ', Signature=' + EncodingUtil.convertToHex(signature);
        req.setHeader('Authorization', authHeader);
        req.setHeader('x-amz-date', iso8601Time);
    }

    public String generatePresignedUrl(String fileName) {
        String httpMethod = 'PUT';
        Datetime dt = Datetime.now();
        String iso8601Date = dt.formatGmt('yyyyMMdd');
        String iso8601Time = dt.formatGmt('yyyyMMdd\'T\'HHmmss\'Z\'');

        String host = this.bucketName + '.' + this.service + '.' + this.region + '.amazonaws.com';
        String canonicalURI = '/' + fileName;
        
        String canonicalQueryString = 'X-Amz-Algorithm=AWS4-HMAC-SHA256' +
            '&X-Amz-Credential=' + EncodingUtil.urlEncode(this.accessKey + '/' + iso8601Date + '/' + this.region + '/' + this.service + '/aws4_request', 'UTF-8') +
            '&X-Amz-Date=' + iso8601Time +
            '&X-Amz-Expires=3600' +
            '&X-Amz-Security-Token=' + EncodingUtil.urlEncode(this.sessionToken, 'UTF-8') +
            '&X-Amz-SignedHeaders=host';

        String canonicalRequest = httpMethod + '\n' + canonicalURI + '\n' + canonicalQueryString + '\n' + 'host:' + host + '\n\n' + 'host' + '\n' + 'UNSIGNED-PAYLOAD';
        String stringToSign = 'AWS4-HMAC-SHA256\n' + iso8601Time + '\n' + iso8601Date + '/' + this.region + '/' + this.service + '/aws4_request\n' + EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', Blob.valueOf(canonicalRequest)));
        
        Blob signingKey = getSigningKey(this.secretKey, iso8601Date, this.region, this.service);
        Blob signature = Crypto.generateMac('hmacSHA256', Blob.valueOf(stringToSign), signingKey);
        String signatureHex = EncodingUtil.convertToHex(signature);

        String endpoint = 'https://' + host + canonicalURI;
        String presignedUrl = endpoint + '?' + canonicalQueryString + '&X-Amz-Signature=' + signatureHex;
        
        return presignedUrl;
    }

    private Blob getSigningKey(String key, String dateStamp, String regionName, String serviceName) {
        Blob kDate = Crypto.generateMac('hmacSHA256', Blob.valueOf(dateStamp), Blob.valueOf('AWS4' + key));
        Blob kRegion = Crypto.generateMac('hmacSHA256', Blob.valueOf(regionName), kDate);
        Blob kService = Crypto.generateMac('hmacSHA256', Blob.valueOf(serviceName), kRegion);
        Blob kSigning = Crypto.generateMac('hmacSHA256', Blob.valueOf('aws4_request'), kService);
        return kSigning;
    }
}