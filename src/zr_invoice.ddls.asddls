@AccessControl.authorizationCheck: #CHECK
@EndUserText.label: '##GENERATED Invoice Processing'
define root view entity ZR_INVOICE
  as select from zinvoice as Invoice
{
  key invoice_uuid as InvoiceUUID,
  internal_reference_number as InternalReferenceNumber,
  invoice_receipt_date as InvoiceReceiptDate,
  due_date as DueDate,
  vendor_vat_number as VendorVatNumber,
  @Semantics.amount.currencyCode: 'Currency'
  subtotal as Subtotal,
  currency as Currency,
  @Semantics.amount.currencyCode: 'Currency'
  total as Total,
  @Semantics.amount.currencyCode: 'Currency'
  amount_due as AmountDue,
  @Semantics.amount.currencyCode: 'Currency'
  tax as Tax,
  vendor_address as VendorAddress,
  vendor_name as VendorName,
  mimetype as Mimetype,
  filename as Filename,
  tmp_mimetype as TmpMimetype,
  tmp_filename as TmpFilename,
  tmp_attachment as TmpAttachment,
  @Semantics.user.createdBy: true
  local_created_by as LocalCreatedBy,
  @Semantics.systemDateTime.createdAt: true
  local_created_at as LocalCreatedAt,
  @Semantics.user.localInstanceLastChangedBy: true
  local_last_changed_by as LocalLastChangedBy,
  @Semantics.systemDateTime.localInstanceLastChangedAt: true
  local_last_changed_at as LocalLastChangedAt,
  @Semantics.systemDateTime.lastChangedAt: true
  last_changed_at as LastChangedAt
  
}
