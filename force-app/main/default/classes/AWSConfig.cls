//class developed for singleton pattern
public class AWSConfig {
    private static AWSConfig awsConfigInstance = NULL;
    private AWS_Configuration__mdt config;
    private AWSConfig(String developerName){
        config = [
            SELECT AWS_Access_Key__c, AWS_Region__c, AWS_Secret_Key__c, S3_Bucket_Name__c, IAM_Role_ARN__c
            FROM AWS_Configuration__mdt WHERE DeveloperName = :developerName
            LIMIT 1
        ];
    }
    public static AWSConfig getAwsConfigInstance(String developerName){
        if(awsConfigInstance == NULL){
            awsConfigInstance = new AWSConfig(developerName);
        }
        return awsConfigInstance;
    }
    public String getAccessKey(){
        return config.AWS_Access_Key__c;
    }
    public String getRegion(){
        return config.AWS_Region__c;
    }
    public String getSecretKey(){
        return config.AWS_Secret_Key__c;
    }
    public String getBucketName(){
        return config.S3_Bucket_Name__c;
    }
}