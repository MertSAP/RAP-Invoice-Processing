@AccessControl.authorizationCheck: #CHECK
@EndUserText.label: 'Invoice Items Projection View'
@Metadata.allowExtensions: true
@Metadata.ignorePropagatedAnnotations: true
define view entity ZC_INVOICE_ITEM as projection on ZR_INVOICE_ITEM
{
    key InvoiceUUID,
    key ItemNum,
   Quantity,
    Description,
     @Semantics.amount.currencyCode: 'Currency'
    UnitPrice,
     @Semantics.amount.currencyCode: 'Currency'
    LinePrice,
    Currency,
    LocalLastChangedAt,
    _Invoice: redirected to parent ZC_INVOICE
}
