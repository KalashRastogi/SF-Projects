public with sharing class S3Controller {
	@AuraEnabled(cacheable=false)
    public static String getPreassignedUrl(String fileName){
        try{
            S3Service service = new S3Service();
            System.debug(fileName);
            return service.generatePreSignedUrl(fileName);
        } catch(Exception e){
            throw new AuraHandledException(e.getMessage());
        }
    }
}