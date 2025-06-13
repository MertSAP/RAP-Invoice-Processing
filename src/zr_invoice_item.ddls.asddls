@AccessControl.authorizationCheck: #CHECK
@Metadata.allowExtensions: true
@EndUserText.label: 'Invocie Item Table'
define view entity ZR_INVOICE_ITEM as select from zinvoice_item as InvoiceItems
association        to parent ZR_INVOICE as _Invoice        on  $projection.InvoiceUUID = _Invoice.InvoiceUUID
{   
    key invoice_uuid as InvoiceUUID,
    key item_num as ItemNum,
    quantity as Quantity,
    description as Description,
    @Semantics.amount.currencyCode: 'Currency'
    unit_price as UnitPrice,
    @Semantics.amount.currencyCode: 'Currency'
    line_price as LinePrice,
    currency as Currency,
    @Semantics.systemDateTime.localInstanceLastChangedAt: true
      local_last_changed_at as LocalLastChangedAt,
    _Invoice
}
