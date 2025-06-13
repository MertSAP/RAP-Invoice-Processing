@AccessControl.authorizationCheck: #CHECK
@Metadata.allowExtensions: true
@EndUserText.label: 'Projection View for ZR_INVOICE'
@ObjectModel.semanticKey: [ 'InvoiceUUID' ]
define root view entity ZC_INVOICE
  provider contract transactional_query
  as projection on ZR_INVOICE
{
  key     InvoiceUUID,
          InternalReferenceNumber,
          InvoiceReceiptDate,
          InvoiceNumber,
          PONum,
          DueDate,
          VendorVatNumber,
          Subtotal,
          Currency,
          Total,
          AmountDue,
          Tax,
          VendorAddress,
          VendorName,
          Mimetype,
          Filename,
          @Semantics.largeObject:
          { mimeType: 'Mimetype',
          fileName: 'Filename',
          contentDispositionPreference: #INLINE }

          @ObjectModel.virtualElementCalculatedBy: 'ABAP:ZCL_INVOICE_RETRIEVAL'
  virtual attachment : zfile_attachment,
          TmpMimetype,
          TmpFilename,
          @Semantics.largeObject:
                      { mimeType: 'TmpMimetype',
                      fileName: 'TmpFilename',
                      contentDispositionPreference: #INLINE }
          TmpAttachment,
          LocalLastChangedAt,
           _InvoiceItems : redirected to composition child ZC_INVOICE_ITEM

}
