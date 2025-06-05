@AccessControl.authorizationCheck: #CHECK
@Metadata.allowExtensions: true
@EndUserText.label: 'Projection View for ZR_INVOICE'
@ObjectModel.semanticKey: [ 'InvoiceUUID' ]
define root view entity ZC_INVOICE
  provider contract transactional_query
  as projection on ZR_INVOICE
{
  key InvoiceUUID,
  InternalReferenceNumber,
  InvoiceReceiptDate,
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
  
  TmpMimetype,
  TmpFilename,
  @Semantics.largeObject:
              { mimeType: 'TmpMimetype',
              fileName: 'TmpFilename',
              contentDispositionPreference: #INLINE }
  TmpAttachment,
  LocalLastChangedAt
  
}
