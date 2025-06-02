CLASS LHC_INVOICE DEFINITION INHERITING FROM CL_ABAP_BEHAVIOR_HANDLER.
  PRIVATE SECTION.
    METHODS:
      GET_GLOBAL_AUTHORIZATIONS FOR GLOBAL AUTHORIZATION
        IMPORTING
           REQUEST requested_authorizations FOR Invoice
        RESULT result,
      setInvoiceRefNum FOR DETERMINE ON SAVE
            IMPORTING keys FOR Invoice~setInvoiceRefNum.
ENDCLASS.

CLASS LHC_INVOICE IMPLEMENTATION.
  METHOD GET_GLOBAL_AUTHORIZATIONS.
  ENDMETHOD.
  METHOD setInvoiceRefNum.

  READ ENTITIES OF zr_invoice IN LOCAL MODE
      ENTITY Invoice
        FIELDS ( InternalReferenceNumber )
        WITH CORRESPONDING #( keys )
      RESULT DATA(invoices).

    DELETE invoices WHERE InternalReferenceNumber IS NOT INITIAL.
    CHECK invoices IS NOT INITIAL.

    "Get max Internal Reference Number
    SELECT SINGLE FROM zinvoice FIELDS MAX( internal_reference_number ) INTO @DATA(max_internal_reference_number).

    "update involved instances
    MODIFY ENTITIES OF zr_invoice IN LOCAL MODE
      ENTITY Invoice
        UPDATE FIELDS ( InternalReferenceNumber )
        WITH VALUE #( FOR invoice IN invoices INDEX INTO i (
                           %tky      = invoice-%tky
                           InternalReferenceNumber  = max_internal_reference_number + i ) ).

ENDMETHOD.

ENDCLASS.
