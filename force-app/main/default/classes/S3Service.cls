public class S3Service {
	private String accessKey;
    private String secretKey;
    private String bucketName;
    private String region;
    private String service = 's3';
    
    public S3Service(){
        AWS_Configuration__mdt  config = [
            SELECT AWS_Access_Key__c, AWS_Region__c, AWS_Secret_Key__c, S3_Bucket_Name__c, IAM_Role_ARN__c
            FROM AWS_Configuration__mdt WHERE DeveloperName = 'Default_S3_Config'
            LIMIT 1
        ];
        
        this.accessKey = config.AWS_Access_Key__c;
        this.secretKey = config.AWS_Secret_Key__c;
        this.bucketName = config.S3_Bucket_Name__c;
        this.region = config.AWS_Region__c;
    }
    
    public String generatePreSignedUrl(String fileName){
        String httpMethod = 'PUT';
        DateTime dt = DateTime.now();
        String iso8601Date = dt.formatGmt('yyyyMMdd');
        String iso8601Time = dt.formatGmt('yyyyMMdd\'T\'HHmmss\'Z\'');
        
        String host = this.bucketName + '.' + this.service + '.' + this.region + '.amazonaws.com';
        String canonicalURI = '/' + fileName;
        
        String canonicalQueryString = 'X-Amz-Algorithm=AWS4-HMAC-SHA256' +
            '&X-Amz-Credential=' + EncodingUtil.urlEncode(this.accessKey + '/' + iso8601Date + '/' + this.region + '/' + this.service + '/aws4_request', 'UTF-8') +
            '&X-Amz-Date=' + iso8601Time +
            '&X-Amz-Expires=3600' + // URL is valid for 1 hour (3600 seconds)
            '&X-Amz-SignedHeaders=host';
        
        String canonicalRequest = httpMethod + '\n' +
            canonicalURI + '\n' +
            canonicalQueryString + '\n' +
            'host:' + host + '\n\n' +
            'host' + '\n' +
            'UNSIGNED-PAYLOAD';
        
        // *** Step 2: Create a "String to Sign" ***
        // This combines metadata about the request with the canonical request hash.
        String stringToSign = 'AWS4-HMAC-SHA256\n' +
            iso8601Time + '\n' +
            iso8601Date + '/' + this.region + '/' + this.service + '/aws4_request\n' +
            EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', Blob.valueOf(canonicalRequest)));

        // *** Step 3: Calculate the Signature ***
        // This is the core cryptographic part. It uses the secret key to create the signature.
        Blob signingKey = getSigningKey(this.secretKey, iso8601Date, this.region, this.service);
        Blob signature = Crypto.generateMac('hmacSHA256', Blob.valueOf(stringToSign), signingKey);
        String signatureHex = EncodingUtil.convertToHex(signature);

        // *** Step 4: Assemble the final URL ***
        String endpoint = 'https://' + host + canonicalURI;
        String presignedUrl = endpoint + '?' + canonicalQueryString + '&X-Amz-Signature=' + signatureHex;
        
        return presignedUrl;
    }
    
    // Helper method to generate the derived signing key required by AWS.
    private Blob getSigningKey(String key, String dateStamp, String regionName, String serviceName) {
        Blob kDate = Crypto.generateMac('hmacSHA256', Blob.valueOf(dateStamp), Blob.valueOf('AWS4' + key));
        Blob kRegion = Crypto.generateMac('hmacSHA256', Blob.valueOf(regionName), kDate);
        Blob kService = Crypto.generateMac('hmacSHA256', Blob.valueOf(serviceName), kRegion);
        Blob kSigning = Crypto.generateMac('hmacSHA256', Blob.valueOf('aws4_request'), kService);
        return kSigning;
    }
}