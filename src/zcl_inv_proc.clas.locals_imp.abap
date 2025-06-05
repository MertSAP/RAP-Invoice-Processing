CLASS lhc_invoice DEFINITION INHERITING FROM cl_abap_behavior_handler.
  PRIVATE SECTION.
    METHODS:
      get_global_authorizations FOR GLOBAL AUTHORIZATION
        IMPORTING
        REQUEST requested_authorizations FOR Invoice
        RESULT result,
      setInvoiceRefNum FOR DETERMINE ON SAVE
        IMPORTING keys FOR Invoice~setInvoiceRefNum,
      uploadToS3 FOR DETERMINE ON SAVE
        IMPORTING keys FOR Invoice~uploadToS3.
ENDCLASS.

CLASS lhc_invoice IMPLEMENTATION.
  METHOD get_global_authorizations.
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

  METHOD uploadToS3.
    DATA: s3_successfull    TYPE abap_bool.

    READ ENTITIES OF zr_invoice IN LOCAL MODE
    ENTITY Invoice ALL FIELDS WITH CORRESPONDING #(  keys )
    RESULT FINAL(lt_invoices_entity).


    LOOP AT lt_invoices_entity INTO DATA(invoice_entity).
      IF invoice_entity-TmpAttachment IS  INITIAL.
        CONTINUE.
      ENDIF.
      DATA(storage_helper) = NEW zcl_invoice_storage(  invoice_entity-InternalReferenceNumber ).

      TRY.
          s3_successfull = abap_true.
          storage_helper->put_object( iv_filename     = invoice_entity-TmpFilename
                                      iv_old_filename = invoice_entity-Filename
                                      iv_body         = invoice_entity-TmpAttachment ).
        CATCH cx_root.

          INSERT VALUE #(  %tky   =  invoice_entity-%tky
                 %element-TmpAttachment =  if_abap_behv=>mk-on
                  %msg        = me->new_message_with_text(  severity = if_abap_behv_message=>severity-error
                                                           text     = 'Unable to store attachment' ) ) INTO TABLE reported-invoice.
          s3_successfull = abap_false.
      ENDTRY.

      IF s3_successfull EQ abap_true.
        invoice_entity-Filename = storage_helper->get_filename( invoice_entity-TmpFilename ).
        invoice_entity-MimeType = invoice_entity-TmpMimetype.
      ELSE.
        CLEAR invoice_entity-Filename.
        CLEAR invoice_entity-MimeType.
      ENDIF.

      CLEAR invoice_entity-TmpAttachment.
      CLEAR invoice_entity-TmpFilename.
      CLEAR invoice_entity-TmpMimetype.

      MODIFY ENTITIES OF zr_invoice IN LOCAL MODE
      ENTITY Invoice
      UPDATE FIELDS ( TmpAttachment TmpFilename TmpMimetype Filename Mimetype )
        WITH VALUE #( ( %key   =  invoice_entity-%key
                  %is_draft     = invoice_entity-%is_draft
                  TmpAttachment = invoice_entity-TmpAttachment
                  TmpFilename = invoice_entity-TmpFilename
                  TmpMimetype = invoice_entity-TmpMimetype
                  Filename = invoice_entity-Filename
                  MimeType =  invoice_entity-MimeType

                  ) )
                  FAILED DATA(failed_update)
                  REPORTED DATA(reported_update).

    ENDLOOP.


  ENDMETHOD.

ENDCLASS.
