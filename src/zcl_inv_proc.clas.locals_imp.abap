CLASS lsc_zr_invoice DEFINITION INHERITING FROM cl_abap_behavior_saver.

  PROTECTED SECTION.

    METHODS adjust_numbers REDEFINITION.

ENDCLASS.

CLASS lsc_zr_invoice IMPLEMENTATION.

  METHOD adjust_numbers.


    IF mapped-invoiceitem IS NOT INITIAL.

      DATA: max_item_id TYPE i VALUE 0.

      LOOP AT mapped-invoiceitem  ASSIGNING FIELD-SYMBOL(<item>).
        <item>-InvoiceUUID = <item>-%tmp-InvoiceUUID.
        IF max_item_id EQ 0.
          SELECT MAX( item_num ) FROM zinvoice_item WHERE invoice_uuid = @<item>-InvoiceUUID INTO @max_item_id .
        ENDIF.

        max_item_id += 10.
        <item>-ItemNum = max_item_id.

      ENDLOOP.

    ENDIF.
  ENDMETHOD.

ENDCLASS.

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
        IMPORTING keys FOR Invoice~uploadToS3,
      get_extract_results IMPORTING
                                    iv_invoice        TYPE zc_invoice
                          EXPORTING et_lineitems      type ztt_invitemline
                                    es_invoice TYPE zc_invoice,
      populateFields FOR MODIFY
        IMPORTING keys FOR ACTION Invoice~populateFields RESULT result,
      populateFieldsFromAttachment FOR DETERMINE ON MODIFY
        IMPORTING keys FOR Invoice~populateFieldsFromAttachment,
      convert_date IMPORTING iv_date_string TYPE string RETURNING VALUE(rv_output) TYPE dats,
      checkDuplicate FOR VALIDATE ON SAVE
        IMPORTING keys FOR Invoice~checkDuplicate,
      get_instance_features FOR INSTANCE FEATURES
        IMPORTING keys REQUEST requested_features FOR Invoice RESULT result.
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

      SELECT SINGLE internal_reference_number INTO @DATA(lv_ref_num) FROM zinvoice WHERE invoice_number = @invoice_entity-InvoiceNumber AND po_num = @invoice_entity-PONum.

      IF lv_ref_num IS NOT INITIAL.
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
        "data: invoice type zc_invoice.
        "  invoice = CORRESPONDING #(  invoice_entity ) .
        " DATA(ls_invoice) = get_extract_results(  invoice ).

        "  invoice_entity = CORRESPONDING #( ls_invoice ).
      ELSE.
        CLEAR invoice_entity-Filename.
        CLEAR invoice_entity-MimeType.
      ENDIF.

      CLEAR invoice_entity-TmpAttachment.
      CLEAR invoice_entity-TmpFilename.
      CLEAR invoice_entity-TmpMimetype.




      MODIFY ENTITIES OF zr_invoice IN LOCAL MODE
      ENTITY Invoice
      UPDATE FIELDS ( TmpAttachment TmpFilename TmpMimetype Filename Mimetype VendorAddress VendorName VendorVatNumber  )
        WITH VALUE #( ( %key   =  invoice_entity-%key
                  %is_draft     = invoice_entity-%is_draft
                  TmpAttachment = invoice_entity-TmpAttachment
                  TmpFilename = invoice_entity-TmpFilename
                  TmpMimetype = invoice_entity-TmpMimetype
                  Filename = invoice_entity-Filename
                  MimeType =  invoice_entity-MimeType
                  VendorAddress  =  invoice_entity-VendorAddress
                  VendorName  =  invoice_entity-VendorName
                  VendorVatNumber  =  invoice_entity-VendorVatNumber
                  ) )
                  FAILED DATA(failed_update)
                  REPORTED DATA(reported_update).

    ENDLOOP.


  ENDMETHOD.

  METHOD get_extract_results.
    DATA(o_extract) = NEW zcl_invoice_extract( ).
    DATA: message TYPE char100.
    DATA: lt_header_fields TYPE ztt_aws_keyvalue.
    DATA: value TYPE string.
    es_invoice = iv_invoice.
    o_extract->get_text_from_document( EXPORTING iv_bytes =  iv_invoice-TmpAttachment IMPORTING ev_header = lt_header_fields ev_message = message et_items = et_lineitems ).

    TRY.
        es_invoice-VendorAddress = lt_header_fields[ key = 'VENDOR_ADDRESS' ]-value.
      CATCH cx_sy_itab_line_not_found.
    ENDTRY.

    TRY.
        es_invoice-VendorName = lt_header_fields[ key = 'VENDOR_NAME' ]-value.
      CATCH cx_sy_itab_line_not_found.
    ENDTRY.

    TRY.
        DATA: due_date TYPE dats.

        value = lt_header_fields[ key = 'DUE_DATE' ]-value.

        es_invoice-DueDate = convert_date( value ).
      CATCH cx_sy_itab_line_not_found.
    ENDTRY.

    TRY.
        DATA: invoice_receipt_date TYPE dats.

        value = lt_header_fields[ key = 'INVOICE_RECEIPT_DATE' ]-value.

        es_invoice-InvoiceReceiptDate = convert_date( value ).
      CATCH cx_sy_itab_line_not_found.
    ENDTRY.

    TRY.

        value = lt_header_fields[ key = 'TOTAL' ]-value.

        IF value+0(1) EQ '$'.
          value = value+1.
        ENDIF.
        es_invoice-Total = value.
      CATCH cx_sy_itab_line_not_found.
    ENDTRY.

    TRY.

        value = lt_header_fields[ key = 'AMOUNT_DUE' ]-value.

        IF value+0(1) EQ '$'.
          value = value+1.
        ENDIF.
        es_invoice-AmountDue = value.
      CATCH cx_sy_itab_line_not_found.
    ENDTRY.

    TRY.

        value = lt_header_fields[ key = 'TAX' ]-value.

        IF value+0(1) EQ '$'.
          value = value+1.
        ENDIF.
        es_invoice-Tax = value.
      CATCH cx_sy_itab_line_not_found.
    ENDTRY.

    TRY.

        value = lt_header_fields[ key = 'SUBTOTAL' ]-value.

        IF value+0(1) EQ '$'.
          value = value+1.
        ENDIF.
        es_invoice-Subtotal = value.
      CATCH cx_sy_itab_line_not_found.
    ENDTRY.

    TRY.

        value = lt_header_fields[ key = 'TAX_PAYER_ID' ]-value.


        es_invoice-VendorVatNumber = value.
      CATCH cx_sy_itab_line_not_found.
    ENDTRY.

    TRY.

        value = lt_header_fields[ key = 'INVOICE_RECEIPT_ID' ]-value.


        es_invoice-InvoiceNumber = value.
      CATCH cx_sy_itab_line_not_found.
    ENDTRY.

    TRY.

        value = lt_header_fields[ key = 'PO_NUMBER' ]-value.


        es_invoice-PONum = value.
      CATCH cx_sy_itab_line_not_found.
    ENDTRY.
  ENDMETHOD.



  METHOD populateFields.


  ENDMETHOD.

  METHOD populateFieldsFromAttachment.
    data: ls_invoice type zc_invoice,
          lt_items type ztt_invitemline.
    " Modify in local mode: BO-related updates that are not relevant for authorization checks
    READ ENTITIES OF zr_invoice IN LOCAL MODE
        ENTITY Invoice
          ALL FIELDS
          WITH CORRESPONDING #( keys )
        RESULT DATA(invoices).

    LOOP AT invoices INTO DATA(invoice_entity).
      IF invoice_entity-TmpAttachment IS INITIAL.
        CONTINUE.
      ENDIF.
      DATA: invoice_cp TYPE zc_invoice.
      invoice_cp = CORRESPONDING #(  invoice_entity ) .
      get_extract_results(  EXPORTING iv_invoice = invoice_cp IMPORTING es_invoice = ls_invoice et_lineitems = lt_items ).

      invoice_entity-VendorName = ls_invoice-VendorName.
      invoice_entity-VendorAddress = ls_invoice-VendorAddress.
      invoice_entity-DueDate = ls_invoice-DueDate.
      invoice_entity-Total = ls_invoice-Total.
      invoice_entity-InvoiceReceiptDate = ls_invoice-InvoiceReceiptDate.
      invoice_entity-Total = ls_invoice-Total.
      invoice_entity-Subtotal = ls_invoice-Subtotal.
      invoice_entity-Tax = ls_invoice-Tax.
      invoice_entity-InvoiceNumber = ls_invoice-InvoiceNumber.
      invoice_entity-PONum = ls_invoice-PONum.
      invoice_entity-AmountDue = ls_invoice-AmountDue.
      invoice_entity-VendorVatNumber = ls_invoice-VendorVatNumber.
      MODIFY ENTITIES OF zr_invoice IN LOCAL MODE
          ENTITY Invoice
          UPDATE FIELDS (  VendorName VendorAddress DueDate InvoiceReceiptDate Total Subtotal Tax AmountDue VendorVatNumber  InvoiceNumber PONum )
            WITH VALUE #( ( %key   =  invoice_entity-%key
                      %is_draft     = invoice_entity-%is_draft

                      VendorName  =  invoice_entity-VendorName
                      VendorAddress = invoice_entity-VendorAddress
                      DueDate = invoice_entity-DueDate
                      InvoiceReceiptDate = invoice_entity-InvoiceReceiptDate
                      Total = invoice_entity-Total
                       Subtotal = ls_invoice-Subtotal
      Tax = ls_invoice-Tax

             AmountDue = ls_invoice-AmountDue
                VendorVatNumber = ls_invoice-VendorVatNumber
                 InvoiceNumber = ls_invoice-InvoiceNumber
      PONum = ls_invoice-PONum
                      ) )
                      FAILED DATA(failed_update)
                      REPORTED DATA(reported_update).

* MODIFY ENTITIES OF zr_invoice IN LOCAL MODE ENTITY Invoice CREATE BY \_InvoiceItems AUTO FILL CID
*           FIELDS ( InvoiceUUID Description ItemNum ) WITH VALUE #( FOR key IN keys (
*
*                        %is_draft = if_abap_behv=>mk-on
*                        %key   =  invoice_entity-%key
*                        %target = VALUE #(
*                         ( %is_draft = if_abap_behv=>mk-on
*                           InvoiceUUID = key-InvoiceUUID
*                           Description = 'sdf' )  ( %is_draft = if_abap_behv=>mk-on
*                           InvoiceUUID = key-InvoiceUUID
*                           Description = 'sdf' )
*                          ) ) )
*      REPORTED data(reported1) FAILED data(failed1) MAPPED data(mapped1).

 MODIFY ENTITIES OF zr_invoice IN LOCAL MODE ENTITY Invoice CREATE BY \_InvoiceItems AUTO FILL CID
           FIELDS ( InvoiceUUID Description ItemNum LinePrice Quantity UnitPrice ) WITH VALUE #( FOR key IN keys (

                        %is_draft = if_abap_behv=>mk-on
                        %key   =  invoice_entity-%key
                        %target = VALUE #(
                         FOR item in lt_items (
                         %is_draft = if_abap_behv=>mk-on
                           InvoiceUUID = key-InvoiceUUID
                           Description = item-description
                           LinePrice = item-line_price
                           UnitPrice = item-unit_price
                           Quantity = item-quantity ) ) ) )
      REPORTED data(reported1) FAILED data(failed1) MAPPED data(mapped1).
    ENDLOOP.


  ENDMETHOD.

  METHOD convert_date.
    DATA(iv_input) = iv_date_string.
    DATA(iv_input_formated) = iv_input.
    DATA: html TYPE string,
          repl TYPE string.

    repl = `-`.  " Match any digit
    iv_input = replace( val   = iv_input
                    pcre  = repl
                    with  = `.`
                    occ   =   0 ).
    repl = `/`.
    iv_input = replace( val   = iv_input
                    pcre  = repl
                    with  = `.`
                    occ   =   0 ).

    repl = `-`.  " Match any digit
    iv_input_formated = replace( val   = iv_input
                    pcre  = repl
                    with  = `.`
                    occ   =   0 ).
    repl = `/`.
    iv_input_formated = replace( val   = iv_input_formated
                    pcre  = repl
                    with  = `.`
                    occ   =   0 ).
    repl = `\d`.
    iv_input_formated = replace( val   = iv_input_formated
                    pcre  = repl
                    with  = `#`
                    occ   =   0 ).

    repl = `[A-Za-z]`.   " Match any digit
    iv_input_formated = replace( val   = iv_input_formated
                    pcre  = repl
                    with  = `*`
                    occ   =   0 ).



    DATA: lv_date TYPE d.

    IF iv_input_formated  EQ '####.##.##'. " 2025-01-03
      SPLIT iv_input AT '.' INTO DATA(lv_y) DATA(lv_m) DATA(lv_d).
      rv_output = |{ lv_y }{ lv_m }{ lv_d }|.
    ELSEIF iv_input_formated  EQ '##.##.####'. " 01-01-2025
      SPLIT iv_input AT '.' INTO lv_d lv_m lv_y.
      rv_output = |{ lv_y }{ lv_m }{ lv_d }|.
    ELSEIF iv_input_formated CA ' '. " 13 Jun 2025
      SPLIT iv_input AT ' ' INTO lv_d DATA(lv_mon) lv_y.
      lv_mon = lv_mon+0(3).
      " Convert month name to number
      DATA(date_String) = to_upper( |{ lv_d } { lv_mon } { lv_y } | ).


      CALL FUNCTION 'CONVERSION_EXIT_SDATE_INPUT'
        EXPORTING
          input  = date_String
        IMPORTING
          output = rv_output.

    ELSE.

    ENDIF.

  ENDMETHOD.
  METHOD checkDuplicate.

    READ ENTITIES OF zr_invoice IN LOCAL MODE
        ENTITY Invoice
          ALL FIELDS
          WITH CORRESPONDING #( keys )
        RESULT DATA(invoices).

    LOOP AT invoices INTO DATA(invoice_entity).

      SELECT SINGLE internal_reference_number INTO @DATA(lv_ref_num) FROM zinvoice WHERE invoice_number = @invoice_entity-InvoiceNumber AND po_num = @invoice_entity-PONum.

      IF lv_ref_num IS NOT INITIAL.
        APPEND VALUE #( %tky = invoice_entity-%tky ) TO failed-invoice.

        APPEND VALUE #( %tky                = invoice_entity-%tky
                        %state_area         = 'CHECK_DUPLICATE'
                        %msg                = new_message_with_text( severity = if_abap_behv_message=>severity-error
                                                                      text = |Duplicate detected. See Invoice: { lv_ref_num }| )
                      ) TO reported-invoice.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD get_instance_features.

  ENDMETHOD.

ENDCLASS.
