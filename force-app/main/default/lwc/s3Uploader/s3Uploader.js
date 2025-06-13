import { LightningElement } from 'lwc';
import {ShowToastEvent} from 'lightning/platformShowToastEvent';

import getPresignedUrl from '@salesforce/apex/S3Controller.getPreassignedUrl';
export default class S3Uploader extends LightningElement {
    fileName = '';
    isLoading = false;
    file;

    handleFileChange(event){
        if(event.target.files.length > 0){
            this.file = event.target.files[0];
            this.fileName = this.file.name; 
            this.getS3UrlAndUpload();
        }
    }

    async getS3UrlAndUpload() {
        this.isLoading = true;

        try {
            // 1. Call Apex to get the pre-signed URL
            const presignedUrl = await getPresignedUrl({ fileName: this.fileName });
            
            // 2. Use the URL to upload the file directly to S3
            await this.uploadToS3(presignedUrl);

            // 3. Show a success message
            this.showToast('Success', 'File uploaded successfully!', 'success');

        } catch (error) {
            console.error('Error during upload: ', error);
            this.showToast('Error', 'There was an error during upload. See console for details.', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    async uploadToS3(presignedUrl) {
        console.log('Uploading to S3...');
        
        // The fetch() API is a standard browser feature for making HTTP requests
        const response = await fetch(presignedUrl, {
            method: 'PUT',
            body: this.file,
            headers: {
                // The Content-Type header is important for S3 to correctly store the file
                'Content-Type': this.file.type || 'application/octet-stream'
            }
        });

        if (!response.ok) {
            // If the upload was not successful, throw an error to be caught by the calling function
            const errorText = await response.text();
            throw new Error(`S3 responded with an error: ${errorText}`);
        }
    }

    // Helper function to show toast messages
    showToast(title, message, variant) {
        const event = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant,
        });
        this.dispatchEvent(event);
    }
}