************************************************************************
* Project     : Erajaya Columbus                                       *
* RICEF Name  : IRQ-1502                                               *
* Program Name: ZFI_AR_PROM_EXP_REAL_TEMP                              *
* Description : Claimable Expense - OO refactor of                     *
*               ZFI_AR_PROM_EXP_REAL                                   *
* Create By   : Gregorius Erico Napis                                  *
* Create Date : 22.10.2026                                             *
* TR No.      : DS4K930189                                             *
*----------------------------------------------------------------------
* Modification History                                                 *
*----------------------------------------------------------------------
* Change ID.  Name        Date       Request No.    Defect/CR No.      *
* Description:                                                         *
*----------------------------------------------------------------------
* CH001      GNAPIS      22-OCT-26  DS4K930189    IS:NNNNNN            *
* Description: Copy of ZFI_AR_PROM_EXP_REAL refactored into local      *
*              classes. Subroutines replaced by OO processors,         *
*              duplicated ALV / BAPI-return / configuration code       *
*              consolidated, dead code and dynpro modules removed.     *
*----------------------------------------------------------------------
* CH002      GNAPIS      22-OCT-26  DS4K930189    IS:NNNNNN            *
* Description: Synchronised with ZFI_AR_PROM_EXP_REAL: AR document read*
*              inside Open SQL (+doc_ar, BSID/BSAD union), reversed MM *
*              invoices excluded via RBKP-STBLG, business area added,  *
*              amounts converted with BAPI_CURRENCY_CONV_TO_EXTERNAL,  *
*              simulate-before-post enforced in Mode A, FB03/MIR4      *
*              drilldown on hotspot, Mode B restricted to the AR doc   *
*              type and the creating transaction code.                 *
*----------------------------------------------------------------------
* CH003      GNAPIS      22-OCT-26  DS4K930189    IS:NNNNNN            *
* Description: Performance - redundant de-duplication removed from the *
*              +doc_ar CTE. UNION already de-duplicates, so the two    *
*              branch DISTINCT clauses were dropped. KUNNR is not used *
*              after the CTE and only widened the result, so it was    *
*              removed as well. The company code restriction moved from*
*              the join condition into WHERE. Result set unchanged.    *
*----------------------------------------------------------------------
* CH004      GNAPIS      22-OCT-26  DS4K930189    IS:NNNNNN            *
* Description: Aligned with the ABAP Standard steering. Internal       *
*              table joins marked ##DB_FEATURE_MODE and guarded        *
*              with IS NOT INITIAL, EXCEPTIONS declared and SY-SUBRC   *
*              checked on both posting interface calls, skip           *
*              messages carry the Skip: prefix plus key data,          *
*              EXPORTING made explicit on multi-parameter calls,       *
*              test mode now shows a yellow icon instead of green,     *
*              P_TEST typed CHAR1 with an ABAP_TRUE default, BDC       *
*              control literals replaced by local constants.           *
*----------------------------------------------------------------------*
REPORT zfi_ar_prom_exp_real_temp.

*---------------------------------------------------------------------*
* Global constants
*---------------------------------------------------------------------*
CONSTANTS:
  gc_cfg_prog    TYPE programm        VALUE 'ZFI_AR_PROM_EXP_REAL' ##NO_TEXT,
  gc_curr        TYPE waers           VALUE 'IDR'                  ##NO_TEXT,
  gc_vgabe_inv   TYPE vgabe           VALUE '2',
  gc_tax_code    TYPE mwskz           VALUE 'V0'                   ##NO_TEXT,
  gc_auglv       TYPE c LENGTH 8      VALUE 'UMBUCHNG'             ##NO_TEXT,
  gc_sgfunc      TYPE c LENGTH 1      VALUE 'C',
  gc_customer    TYPE bseg-koart      VALUE 'D',
  gc_tcode_clr   TYPE tcode           VALUE 'FB05'                 ##NO_TEXT,
  gc_tcode_fi    TYPE tcode           VALUE 'FB03'                 ##NO_TEXT,
  gc_tcode_mm    TYPE tcode           VALUE 'MIR4'                 ##NO_TEXT,
  gc_debit       TYPE shkzg           VALUE 'S',
  gc_credit      TYPE shkzg           VALUE 'H',
  gc_msgty_e     TYPE symsgty         VALUE 'E',
  gc_msgty_a     TYPE symsgty         VALUE 'A',
  gc_simulated   TYPE c LENGTH 10     VALUE 'SIMULATED'            ##NO_TEXT,
  gc_reason_rev  TYPE c LENGTH 2      VALUE '01',
  gc_ext_struc   TYPE c LENGTH 30     VALUE 'ZCLEAR_REBZG'         ##NO_TEXT,
  gc_mode_a      TYPE c LENGTH 1      VALUE 'A',
  gc_mode_b      TYPE c LENGTH 1      VALUE 'B',
  gc_st_open     TYPE c LENGTH 1      VALUE 'O',
  gc_st_realized TYPE c LENGTH 1      VALUE 'R',
  gc_st_error    TYPE c LENGTH 1      VALUE 'E',
  gc_st_blocked  TYPE c LENGTH 1      VALUE 'B'.

CONSTANTS:
  gc_fc_post    TYPE sy-ucomm VALUE 'POST'         ##NO_TEXT,
  gc_fc_simu    TYPE sy-ucomm VALUE 'SIMU'         ##NO_TEXT,
  gc_fc_sel_all TYPE sy-ucomm VALUE 'SELECT_ALL'   ##NO_TEXT,
  gc_fc_des_all TYPE sy-ucomm VALUE 'DESELECT_ALL' ##NO_TEXT.

*---------------------------------------------------------------------*
* Global types
*---------------------------------------------------------------------*
TYPES:
  gty_mode   TYPE c LENGTH 1,
  gtt_mode_a TYPE STANDARD TABLE OF zst_fi_promotion_claim WITH EMPTY KEY,
  gtt_claim  TYPE STANDARD TABLE OF zst_fi_clear_outstanding WITH EMPTY KEY,
  gtr_zuonr  TYPE RANGE OF dzuonr.

TYPES:
  BEGIN OF gty_outst,
    bukrs     TYPE bsid-bukrs,
    belnr     TYPE bsid-belnr,
    gjahr     TYPE bsid-gjahr,
    buzei     TYPE bsid-buzei,
    kunnr     TYPE bsid-kunnr,
    xblnr     TYPE bsid-xblnr,
    prctr     TYPE bsid-prctr,
    gsber     TYPE bsid-gsber,
    wrbtr     TYPE bsid-wrbtr,
    remaining TYPE bsid-wrbtr,
    waers     TYPE bsid-waers,
  END OF gty_outst,
  gtt_outst TYPE STANDARD TABLE OF gty_outst WITH EMPTY KEY.

*---------------------------------------------------------------------*
* Dummy fields for SELECT-OPTIONS
*---------------------------------------------------------------------*
DATA:
  gv_bukrs       TYPE bkpf-bukrs,
  gv_doc_type_po TYPE ekko-bsart,
  gv_doc_type_ar TYPE bkpf-blart,
  gv_ebeln       TYPE ekko-ebeln,
  gv_ebelp       TYPE ekpo-ebelp,
  gv_lifnr       TYPE ekko-lifnr,
  gv_bedat       TYPE ekko-bedat,
  gv_belnr       TYPE bsid-belnr,
  gv_zuonr       TYPE bsid-zuonr,
  gv_kunnr       TYPE bsid-kunnr,
  gv_budat       TYPE bsid-budat.

*---------------------------------------------------------------------*
* Selection screen
*---------------------------------------------------------------------*
SELECTION-SCREEN BEGIN OF BLOCK b2 WITH FRAME TITLE TEXT-b02.
  SELECT-OPTIONS s_bukrs FOR gv_bukrs OBLIGATORY NO INTERVALS NO-EXTENSION MEMORY ID buk.
  SELECT-OPTIONS s_bsart FOR gv_doc_type_po MODIF ID ma NO INTERVALS.
  SELECT-OPTIONS:
    s_ebeln FOR gv_ebeln MODIF ID ma,
    s_ebelp FOR gv_ebelp MODIF ID ma,
    s_lifnr FOR gv_lifnr MODIF ID ma,
    s_bedat FOR gv_bedat MODIF ID ma.

  SELECT-OPTIONS:
    s_belnr FOR gv_belnr MODIF ID mb,
    s_zuonr FOR gv_zuonr MODIF ID mb,
    s_pebel FOR gv_ebeln MODIF ID mb,
    s_pebep FOR gv_ebelp MODIF ID mb NO-DISPLAY,
    s_kunnr FOR gv_kunnr MODIF ID mb,
    s_arbud FOR gv_budat MODIF ID mb.
SELECTION-SCREEN END OF BLOCK b2.

SELECTION-SCREEN BEGIN OF BLOCK b3 WITH FRAME TITLE TEXT-b03.
  PARAMETERS:
    p_kunnr TYPE kunnr MODIF ID ma,
    p_budat TYPE budat DEFAULT sy-datum MODIF ID ma,
    p_bldat TYPE bldat DEFAULT sy-datum MODIF ID ma,
    p_xblnr TYPE xblnr MODIF ID ma.
  PARAMETERS:
    p_gjahr TYPE gjahr DEFAULT sy-datum(4) MODIF ID mb,
    p_clrdt TYPE budat DEFAULT sy-datum MODIF ID mb.
SELECTION-SCREEN END OF BLOCK b3.

SELECTION-SCREEN BEGIN OF BLOCK b0 WITH FRAME TITLE TEXT-b00.
  PARAMETERS:
    p_mode_a RADIOBUTTON GROUP md USER-COMMAND mode DEFAULT 'X',
    p_mode_b RADIOBUTTON GROUP md.
SELECTION-SCREEN END OF BLOCK b0.

*PARAMETERS p_test TYPE char1 AS CHECKBOX DEFAULT abap_true MODIF ID ma .

*---------------------------------------------------------------------*
* CLASS DEFINITIONS
*---------------------------------------------------------------------*
CLASS lcl_util DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS:
      raise_sy_message,

      bapi_error IMPORTING it_return         TYPE bapiret2_t
                 RETURNING VALUE(rv_message) TYPE bapiret2-message,

      has_bapi_error IMPORTING it_return       TYPE bapiret2_t
                     RETURNING VALUE(rv_error) TYPE abap_bool,

      to_external IMPORTING VALUE(iv_amount) TYPE any
                  RETURNING VALUE(rv_amount) TYPE bapicurr-bapicurr,

      set_fcat IMPORTING VALUE(iv_label)     TYPE string
                         VALUE(iv_edit)      TYPE abap_bool  DEFAULT abap_false
                         VALUE(iv_checkbox)  TYPE abap_bool  DEFAULT abap_false
                         VALUE(iv_tech)      TYPE abap_bool  DEFAULT abap_false
                         VALUE(iv_hotspot)   TYPE abap_bool  DEFAULT abap_false
                         VALUE(iv_f4)        TYPE abap_bool  DEFAULT abap_false
                         VALUE(iv_outputlen) TYPE lvc_outlen DEFAULT 0
               CHANGING  cw_fcat             TYPE lvc_s_fcat,

      disable_cells IMPORTING it_fieldname    TYPE string_table
                    RETURNING VALUE(rt_style) TYPE lvc_t_styl.
ENDCLASS.

CLASS lcl_config DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS:
      load,
      doc_type_po       RETURNING VALUE(rr_bsart) TYPE tms_t_bsart_range,
      doc_type_ap       RETURNING VALUE(rv_blart) TYPE bkpf-blart,
      doc_type_ar       RETURNING VALUE(rv_blart) TYPE bkpf-blart,
      doc_type_clearing RETURNING VALUE(rv_blart) TYPE bkpf-blart.

  PRIVATE SECTION.
    CONSTANTS:
      lc_var_po  TYPE c LENGTH 30 VALUE 'DOC_TYPE_PO'       ##NO_TEXT,
      lc_var_ap  TYPE c LENGTH 30 VALUE 'DOC_TYPE_AP'       ##NO_TEXT,
      lc_var_ar  TYPE c LENGTH 30 VALUE 'DOC_TYPE_AR'       ##NO_TEXT,
      lc_var_clr TYPE c LENGTH 30 VALUE 'DOC_TYPE_CLEARING' ##NO_TEXT.

    CLASS-DATA:
      gr_bsart    TYPE tms_t_bsart_range,
      gv_blart_ap TYPE bkpf-blart,
      gv_blart_ar TYPE bkpf-blart,
      gv_blart_cl TYPE bkpf-blart.

    CLASS-METHODS read IMPORTING iv_name  TYPE c
                       CHANGING  cv_value TYPE any OPTIONAL
                                 cr_value TYPE STANDARD TABLE OPTIONAL.
ENDCLASS.

CLASS lcl_alv_base DEFINITION ABSTRACT.
  PUBLIC SECTION.
    METHODS:
      select   ABSTRACT,
      display  ABSTRACT,
      has_data ABSTRACT RETURNING VALUE(rv_filled) TYPE abap_bool.

  PROTECTED SECTION.
    DATA mo_grid TYPE REF TO cl_gui_alv_grid.

    METHODS:
      create_grid IMPORTING VALUE(iv_title)       TYPE string
                            it_info               TYPE string_table OPTIONAL
                            VALUE(iv_enter_event) TYPE abap_bool    DEFAULT abap_false
                            it_f4                 TYPE lvc_t_f4     OPTIONAL
                  RETURNING VALUE(ro_grid)        TYPE REF TO cl_gui_alv_grid,

      finish_display,

      optimize_and_refresh,

      get_exclude RETURNING VALUE(rt_exclude) TYPE ui_functions,

      get_layout  RETURNING VALUE(rw_layout)  TYPE lvc_s_layo,

      add_toolbar_button IMPORTING iv_function    TYPE sy-ucomm
                                   iv_icon        TYPE c
                                   VALUE(iv_text) TYPE string OPTIONAL
                                   io_object      TYPE REF TO cl_alv_event_toolbar_set.
ENDCLASS.

CLASS lcl_mode_a DEFINITION FINAL INHERITING FROM lcl_alv_base.
  PUBLIC SECTION.
    METHODS:
      select   REDEFINITION,
      display  REDEFINITION,
      has_data REDEFINITION.

  PRIVATE SECTION.
    DATA:
      mt_data      TYPE gtt_mode_a,
      mv_test      TYPE abap_bool,
      mv_simulated TYPE abap_bool.

    METHODS:
      evaluate_status,
      post,
      post_ap_invoice    CHANGING  cw_claim       TYPE zst_fi_promotion_claim,
      post_ar_invoice    CHANGING  cw_claim       TYPE zst_fi_promotion_claim,
      reverse_ap_invoice CHANGING  cw_claim       TYPE zst_fi_promotion_claim,
      set_selection      IMPORTING iv_sel         TYPE abap_bool,
      build_fieldcat     RETURNING VALUE(rt_fcat) TYPE lvc_t_fcat,

      on_toolbar       FOR EVENT toolbar OF cl_gui_alv_grid
        IMPORTING e_object e_interactive,

      on_user_command  FOR EVENT user_command OF cl_gui_alv_grid
        IMPORTING e_ucomm,

      on_data_changed  FOR EVENT data_changed OF cl_gui_alv_grid
        IMPORTING er_data_changed,

      on_hotspot_click FOR EVENT hotspot_click OF cl_gui_alv_grid
        IMPORTING e_row_id e_column_id.
ENDCLASS.

CLASS lcl_mode_b DEFINITION FINAL INHERITING FROM lcl_alv_base.
  PUBLIC SECTION.
    METHODS:
      select   REDEFINITION,
      display  REDEFINITION,
      has_data REDEFINITION.

  PRIVATE SECTION.
    TYPES ltt_open_item TYPE STANDARD TABLE OF zst_fi_search_help_ar WITH EMPTY KEY.

    DATA:
      mt_claim     TYPE gtt_claim,
      mt_outst     TYPE gtt_outst,
      mv_simulated TYPE abap_bool.

    METHODS:
      build_zuonr_range RETURNING VALUE(rt_range) TYPE gtr_zuonr,
      read_outstanding,
      simulate,
      post_clearing,
      post_single       IMPORTING iw_outst TYPE gty_outst
                        CHANGING  cw_claim TYPE zst_fi_clear_outstanding,
      add_ftpost        IMPORTING iv_stype  TYPE c
                                  iv_count  TYPE i
                                  iv_fnam   TYPE c
                                  iv_fval   TYPE any
                        CHANGING  ct_ftpost TYPE feb_t_ftpost,
      set_selection     IMPORTING iv_sel          TYPE abap_bool,
      build_fieldcat    RETURNING VALUE(rt_fcat)  TYPE lvc_t_fcat,
      open_items_for_f4 IMPORTING iw_claim        TYPE zst_fi_clear_outstanding
                        RETURNING VALUE(rt_items) TYPE ltt_open_item,

      on_toolbar       FOR EVENT toolbar OF cl_gui_alv_grid
        IMPORTING e_object e_interactive,

      on_user_command  FOR EVENT user_command OF cl_gui_alv_grid
        IMPORTING e_ucomm,

      on_data_changed  FOR EVENT data_changed OF cl_gui_alv_grid
        IMPORTING er_data_changed,

      on_value_request FOR EVENT onf4 OF cl_gui_alv_grid
        IMPORTING e_fieldname e_fieldvalue es_row_no
                  er_event_data et_bad_cells e_display,

      on_hotspot_click FOR EVENT hotspot_click OF cl_gui_alv_grid
        IMPORTING e_row_id e_column_id.
ENDCLASS.

CLASS lcl_app DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS:
      initialize,
      modify_screen,
      validate_screen,
      run,
      show,
      get_mode RETURNING VALUE(rv_mode) TYPE gty_mode.

  PRIVATE SECTION.
    CLASS-DATA go_processor TYPE REF TO lcl_alv_base.

    CLASS-METHODS check_period IMPORTING iv_bukrs TYPE bukrs
                                         iv_budat TYPE budat.
ENDCLASS.

*---------------------------------------------------------------------*
* CLASS IMPLEMENTATIONS
*---------------------------------------------------------------------*
CLASS lcl_util IMPLEMENTATION.
  METHOD raise_sy_message.
    IF sy-msgid IS NOT INITIAL AND sy-msgno IS NOT INITIAL.
      MESSAGE ID sy-msgid TYPE 'S' NUMBER sy-msgno
        WITH sy-msgv1 sy-msgv2 sy-msgv3 sy-msgv4 DISPLAY LIKE 'E'.
    ENDIF.
  ENDMETHOD.

  METHOD has_bapi_error.
    rv_error = xsdbool( line_exists( it_return[ type = gc_msgty_e ] )
                     OR line_exists( it_return[ type = gc_msgty_a ] ) ).
  ENDMETHOD.

  METHOD bapi_error.
    READ TABLE it_return INTO DATA(lw_return) WITH KEY type = gc_msgty_e.
    IF sy-subrc <> 0.
      READ TABLE it_return INTO lw_return WITH KEY type = gc_msgty_a.
    ENDIF.
    IF sy-subrc = 0.
      rv_message = lw_return-message.
    ENDIF.
  ENDMETHOD.

  METHOD to_external.
    "BAPI amount fields expect the external representation
    CALL FUNCTION 'BAPI_CURRENCY_CONV_TO_EXTERNAL'
      EXPORTING
        currency        = gc_curr
        amount_internal = iv_amount
      IMPORTING
        amount_external = rv_amount.
  ENDMETHOD.

  METHOD set_fcat.
    cw_fcat-edit       = iv_edit.
    cw_fcat-checkbox   = iv_checkbox.
    cw_fcat-tech       = iv_tech.
    cw_fcat-hotspot    = iv_hotspot.
    cw_fcat-f4availabl = iv_f4.
    cw_fcat-seltext    = iv_label.
    cw_fcat-scrtext_s  = iv_label.
    cw_fcat-scrtext_m  = iv_label.
    cw_fcat-scrtext_l  = iv_label.
    IF iv_outputlen > 0.
      cw_fcat-outputlen = iv_outputlen.
    ENDIF.
  ENDMETHOD.

  METHOD disable_cells.
    rt_style = VALUE #( FOR lv_field IN it_fieldname
                        ( fieldname = lv_field
                          style     = cl_gui_alv_grid=>mc_style_disabled ) ).
  ENDMETHOD.
ENDCLASS.

CLASS lcl_config IMPLEMENTATION.
  METHOD load.
    read( EXPORTING iv_name = lc_var_po  CHANGING cr_value = gr_bsart ).
    read( EXPORTING iv_name = lc_var_ap  CHANGING cv_value = gv_blart_ap ).
    read( EXPORTING iv_name = lc_var_ar  CHANGING cv_value = gv_blart_ar ).
    read( EXPORTING iv_name = lc_var_clr CHANGING cv_value = gv_blart_cl ).
  ENDMETHOD.

  METHOD read.
    IF cv_value IS SUPPLIED.
      zcl_ca_utility=>read_variable_value(
        EXPORTING
          iv_zzprog                   = gc_cfg_prog
          iv_zzname                   = iv_name
        IMPORTING
          ev_p_value                  = cv_value
        EXCEPTIONS
          ex_read_parameter_not_found = 1
          OTHERS                      = 2 ).
    ENDIF.

    IF cr_value IS SUPPLIED.
      zcl_ca_utility=>read_variable_value(
        EXPORTING
          iv_zzprog                   = gc_cfg_prog
          iv_zzname                   = iv_name
        IMPORTING
          et_s_value                  = cr_value
        EXCEPTIONS
          ex_read_parameter_not_found = 1
          OTHERS                      = 2 ).
    ENDIF.

    IF sy-subrc <> 0.
      IF sy-msgid IS NOT INITIAL AND sy-msgno IS NOT INITIAL.
        lcl_util=>raise_sy_message( ).
      ELSE.
        MESSAGE s398(00) WITH 'Configuration not found:' iv_name
          DISPLAY LIKE 'E' ##NO_TEXT.
      ENDIF.
    ENDIF.
  ENDMETHOD.

  METHOD doc_type_po.
    rr_bsart = gr_bsart.
  ENDMETHOD.

  METHOD doc_type_ap.
    rv_blart = gv_blart_ap.
  ENDMETHOD.

  METHOD doc_type_ar.
    rv_blart = gv_blart_ar.
  ENDMETHOD.

  METHOD doc_type_clearing.
    rv_blart = gv_blart_cl.
  ENDMETHOD.
ENDCLASS.

CLASS lcl_alv_base IMPLEMENTATION.
  METHOD create_grid.
    DATA lv_line TYPE sdydo_text_element.

    DATA(lo_splitter) = NEW cl_gui_splitter_container(
                          parent                  = cl_gui_container=>default_screen
                          no_autodef_progid_dynnr = abap_true
                          rows                    = 2
                          columns                 = 1 ).

    lo_splitter->set_row_height( id = 1 height = 10 ).

    DATA(lo_top)    = lo_splitter->get_container( row = 1 column = 1 ).
    DATA(lo_bottom) = lo_splitter->get_container( row = 2 column = 1 ).

    DATA(lo_doc) = NEW cl_dd_document( ).

    lv_line = iv_title.
    lo_doc->add_text( text      = lv_line
                      sap_style = cl_dd_document=>heading ).
    lo_doc->new_line( ).
    lo_doc->new_line( ).

    LOOP AT it_info INTO DATA(lv_info).
      lv_line = lv_info.
      lo_doc->add_text( text      = lv_line
                        sap_style = cl_dd_document=>medium ).
      lo_doc->new_line( ).
    ENDLOOP.

    lo_doc->display_document(
      EXPORTING  parent             = lo_top
      EXCEPTIONS html_display_error = 1
                 OTHERS             = 2 ).
    IF sy-subrc <> 0.
      lcl_util=>raise_sy_message( ).
    ENDIF.

    ro_grid = NEW cl_gui_alv_grid( i_parent = lo_bottom ).
    mo_grid = ro_grid.

    ro_grid->register_edit_event(
      EXPORTING  i_event_id = cl_gui_alv_grid=>mc_evt_modified
      EXCEPTIONS error      = 1
                 OTHERS     = 2 ).
    IF sy-subrc <> 0.
      lcl_util=>raise_sy_message( ).
    ENDIF.

    IF iv_enter_event = abap_true.
      ro_grid->register_edit_event(
        EXPORTING  i_event_id = cl_gui_alv_grid=>mc_evt_enter
        EXCEPTIONS error      = 1
                   OTHERS     = 2 ).
      IF sy-subrc <> 0.
        lcl_util=>raise_sy_message( ).
      ENDIF.
    ENDIF.

    IF it_f4 IS NOT INITIAL.
      ro_grid->register_f4_for_fields( it_f4 ).
    ENDIF.
  ENDMETHOD.

  METHOD finish_display.
    cl_gui_control=>set_focus( control = mo_grid ).
    cl_gui_cfw=>flush( ).
    WRITE: /.
  ENDMETHOD.

  METHOD optimize_and_refresh.
    IF mo_grid IS NOT BOUND.
      RETURN.
    ENDIF.

    mo_grid->get_frontend_layout( IMPORTING es_layout = DATA(lw_layout) ).
    lw_layout-cwidth_opt = abap_true.
    mo_grid->set_frontend_layout( lw_layout ).

    mo_grid->refresh_table_display(
      EXPORTING  is_stable = VALUE lvc_s_stbl( row = abap_true
                                               col = abap_true )
      EXCEPTIONS finished  = 1
                 OTHERS    = 2 ).
    IF sy-subrc <> 0.
      lcl_util=>raise_sy_message( ).
    ENDIF.
  ENDMETHOD.

  METHOD get_exclude.
    rt_exclude = VALUE #(
      ( cl_gui_alv_grid=>mc_fc_loc_append_row )
      ( cl_gui_alv_grid=>mc_fc_loc_delete_row )
      ( cl_gui_alv_grid=>mc_fc_loc_copy_row )
      ( cl_gui_alv_grid=>mc_fc_loc_insert_row )
      ( cl_gui_alv_grid=>mc_fc_loc_cut )
      ( cl_gui_alv_grid=>mc_fc_loc_move_row )
      ( cl_gui_alv_grid=>mc_fc_loc_paste )
      ( cl_gui_alv_grid=>mc_fc_loc_paste_new_row )
      ( cl_gui_alv_grid=>mc_fc_loc_undo )
      ( cl_gui_alv_grid=>mc_fc_url_copy_to_clipboard ) ).
  ENDMETHOD.

  METHOD get_layout.
    rw_layout = VALUE lvc_s_layo( cwidth_opt = abap_true
                                  stylefname = 'STYLE'
                                  no_rowmark = abap_true ).
  ENDMETHOD.

  METHOD add_toolbar_button.
    io_object->mt_toolbar = VALUE #( BASE io_object->mt_toolbar
      ( function  = iv_function
        icon      = iv_icon
        text      = iv_text
        quickinfo = iv_text
        butn_type = 0 ) ).
  ENDMETHOD.
ENDCLASS.

CLASS lcl_mode_a IMPLEMENTATION.
  METHOD has_data.
    rv_filled = xsdbool( mt_data IS NOT INITIAL ).
  ENDMETHOD.

  METHOD select.
    CLEAR mt_data.
*    mv_test = p_test.

    WITH
      +po AS (
        SELECT a~ebeln,
               b~ebelp,
               b~txz01,
               a~lifnr,
               a~waers,
               b~netwr,
               c~name1,
               concat( a~ebeln, b~ebelp ) AS zuonr,
               @p_kunnr                   AS partner
          FROM ekko AS a
          INNER JOIN ekpo AS b ON a~ebeln = b~ebeln
          INNER JOIN lfa1 AS c ON a~lifnr = c~lifnr
          WHERE a~bukrs =  @gv_bukrs
            AND a~bsart IN @s_bsart
            AND a~ebeln IN @s_ebeln
            AND a~lifnr IN @s_lifnr
            AND a~bedat IN @s_bedat
            AND a~frgrl =  @space
            AND a~loekz =  @space
            AND b~ebelp IN @s_ebelp
            AND b~loekz =  @space
            AND b~elikz =  @space ),

      +ekkn AS (
        SELECT DISTINCT a~ebeln, a~ebelp, a~aufnr, a~kostl, a~sakto, a~prctr, a~gsber
          FROM ekkn AS a
          INNER JOIN +po AS b ON a~ebeln = b~ebeln
                             AND a~ebelp = b~ebelp ),

      "Reversed vendor invoices must not count as realized
      +ekbe AS (
        SELECT DISTINCT a~ebeln, a~ebelp, a~gjahr, a~belnr
          FROM ekbe AS a
          INNER JOIN +po AS b  ON a~ebeln = b~ebeln
                              AND a~ebelp = b~ebelp
          INNER JOIN rbkp AS c ON a~belnr = c~belnr
                              AND a~gjahr = c~gjahr
          WHERE a~vgabe = @gc_vgabe_inv
            AND c~stblg = @space ),

      +customer AS (
        SELECT partner, name_org1
          FROM but000
          WHERE partner = @p_kunnr ),

      "Claimable AR already posted for this Assignment - open and cleared.
      "UNION de-duplicates the combined result, so no branch needs DISTINCT.
      "BUKRS / BELNR / GJAHR identify the document and must stay; KUNNR is
      "not read after this CTE and would only multiply rows per line item.
      +doc_ar AS (
        SELECT a~bukrs, a~belnr, a~gjahr, a~zuonr, a~augbl
          FROM bsid_view AS a
          INNER JOIN bkpf AS b ON  a~bukrs = b~bukrs
                               AND a~belnr = b~belnr
                               AND a~gjahr = b~gjahr
          INNER JOIN +po   AS c ON  a~zuonr = c~zuonr
          WHERE a~bukrs = @gv_bukrs
            AND b~stblg IS INITIAL
        UNION
        SELECT a~bukrs, a~belnr, a~gjahr, a~zuonr, a~augbl
          FROM bsad_view AS a
          INNER JOIN bkpf AS b ON  a~bukrs = b~bukrs
                               AND a~belnr = b~belnr
                               AND a~gjahr = b~gjahr
          INNER JOIN +po   AS c ON  a~zuonr = c~zuonr
          WHERE a~bukrs = @gv_bukrs
            AND b~stblg IS INITIAL )

      SELECT a~ebeln,
             a~ebelp,
             a~txz01,
             a~lifnr,
             a~waers,
             a~netwr,
             a~name1,
             a~zuonr,
             b~aufnr,
             b~sakto,
             b~kostl,
             b~prctr,
             b~gsber,
             c~belnr AS belnr_ap,
             c~gjahr AS gjahr,
             e~partner,
             e~name_org1,
             f~belnr AS belnr_ar,
             f~augbl
        FROM +po AS a
        LEFT JOIN +ekkn     AS b ON a~ebeln   = b~ebeln
                                AND a~ebelp   = b~ebelp
        LEFT JOIN +ekbe     AS c ON a~ebeln   = c~ebeln
                                AND a~ebelp   = c~ebelp
        LEFT JOIN +customer AS e ON a~partner = e~partner
        LEFT JOIN +doc_ar   AS f ON a~zuonr   = f~zuonr
        ORDER BY a~ebeln, a~ebelp
        INTO CORRESPONDING FIELDS OF TABLE @mt_data.

    IF mt_data IS INITIAL.
      MESSAGE s398(00) WITH 'No eligible promotion PO found' ##NO_TEXT.
      RETURN.
    ENDIF.

    evaluate_status( ).
  ENDMETHOD.

  METHOD evaluate_status.
    LOOP AT mt_data ASSIGNING FIELD-SYMBOL(<lf_po>).
      CLEAR: <lf_po>-light,
             <lf_po>-status,
             <lf_po>-message,
             <lf_po>-style.

      IF <lf_po>-waers <> gc_curr.
        <lf_po>-light   = gc_st_blocked.
        <lf_po>-message = |Currency { <lf_po>-waers } is not supported.| ##NO_TEXT.
      ENDIF.

      IF <lf_po>-aufnr IS INITIAL
        OR <lf_po>-kostl IS INITIAL
        OR <lf_po>-sakto IS INITIAL
        OR <lf_po>-prctr IS INITIAL.

        <lf_po>-light   = gc_st_error.
        <lf_po>-message = 'No internal order on PO account assignment' ##NO_TEXT.
      ENDIF.

      "V-06: already realized when an AP invoice or a claimable AR exists
      IF <lf_po>-belnr_ap IS NOT INITIAL
        OR <lf_po>-belnr_ar IS NOT INITIAL.
        <lf_po>-light   = gc_st_realized.
        <lf_po>-message = |Already realized under invoice { <lf_po>-belnr_ap }.| ##NO_TEXT.

      ELSEIF <lf_po>-light IS INITIAL.
        <lf_po>-light = gc_st_open.
      ENDIF.

      CASE <lf_po>-light.
        WHEN gc_st_open.
          <lf_po>-status = icon_led_yellow.
        WHEN gc_st_realized.
          <lf_po>-status = icon_led_green.
          <lf_po>-style  = lcl_util=>disable_cells( VALUE #( ( `SEL` ) ) ).
        WHEN gc_st_error OR gc_st_blocked.
          <lf_po>-status = icon_led_red.
          <lf_po>-style  = lcl_util=>disable_cells( VALUE #( ( `SEL` ) ) ).
        WHEN OTHERS.
          <lf_po>-status = icon_led_inactive.
          <lf_po>-style  = lcl_util=>disable_cells( VALUE #( ( `SEL` ) ) ).
      ENDCASE.
    ENDLOOP.
  ENDMETHOD.

  METHOD build_fieldcat.
    CALL FUNCTION 'LVC_FIELDCATALOG_MERGE'
      EXPORTING
        i_structure_name       = 'ZST_FI_PROMOTION_CLAIM'
        i_bypassing_buffer     = abap_true
      CHANGING
        ct_fieldcat            = rt_fcat
      EXCEPTIONS
        inconsistent_interface = 1
        program_error          = 2
        OTHERS                 = 3.
    IF sy-subrc <> 0.
      lcl_util=>raise_sy_message( ).
      RETURN.
    ENDIF.

    LOOP AT rt_fcat ASSIGNING FIELD-SYMBOL(<lf_fcat>).
      CASE <lf_fcat>-fieldname.
        WHEN 'SEL'.
          lcl_util=>set_fcat( EXPORTING iv_label    = `Checkbox`
                                        iv_edit     = abap_true
                                        iv_checkbox = abap_true
                              CHANGING  cw_fcat     = <lf_fcat> ).
        WHEN 'LIGHT'.
          lcl_util=>set_fcat( EXPORTING iv_label = `Status`
                                        iv_tech  = abap_true
                              CHANGING  cw_fcat  = <lf_fcat> ).
        WHEN 'STATUS'.
          lcl_util=>set_fcat( EXPORTING iv_label = `Indicator`
                              CHANGING  cw_fcat  = <lf_fcat> ).
        WHEN 'LIFNR'.
          lcl_util=>set_fcat( EXPORTING iv_label = `Vendor`
                              CHANGING  cw_fcat  = <lf_fcat> ).
        WHEN 'NAME1'.
          lcl_util=>set_fcat( EXPORTING iv_label = `Vendor Name`
                              CHANGING  cw_fcat  = <lf_fcat> ).
        WHEN 'PARTNER'.
          lcl_util=>set_fcat( EXPORTING iv_label = `Customer`
                              CHANGING  cw_fcat  = <lf_fcat> ).
        WHEN 'NAME_ORG1'.
          lcl_util=>set_fcat( EXPORTING iv_label = `Customer Name`
                              CHANGING  cw_fcat  = <lf_fcat> ).
        WHEN 'BELNR_AP'.
          lcl_util=>set_fcat( EXPORTING iv_label   = `AP Invoice Document`
                                        iv_hotspot = abap_true
                              CHANGING  cw_fcat    = <lf_fcat> ).
        WHEN 'BELNR_AR'.
          lcl_util=>set_fcat( EXPORTING iv_label   = `AR Claimable Document`
                                        iv_hotspot = abap_true
                              CHANGING  cw_fcat    = <lf_fcat> ).
        WHEN 'AUGBL'.
          lcl_util=>set_fcat( EXPORTING iv_label   = `Clearing AR`
                                        iv_hotspot = abap_true
                              CHANGING  cw_fcat    = <lf_fcat> ).
        WHEN 'GJAHR'.
          lcl_util=>set_fcat( EXPORTING iv_label = `Fiscal year posted`
                              CHANGING  cw_fcat  = <lf_fcat> ).
        WHEN 'MESSAGE'.
          lcl_util=>set_fcat( EXPORTING iv_label = `Message`
                              CHANGING  cw_fcat  = <lf_fcat> ).
        WHEN OTHERS.
          "keep the DDIC labels
      ENDCASE.
    ENDLOOP.
  ENDMETHOD.

  METHOD display.
    DATA(lt_fcat) = build_fieldcat( ).

    DATA(lv_name) = VALUE #( mt_data[ 1 ]-name_org1 OPTIONAL ).

    DATA(lo_grid) = create_grid(
      EXPORTING
        iv_title = `Expense Realization`
        it_info  = VALUE string_table( ( |Company Code: { gv_bukrs }| )
                                       ( |Customer: { p_kunnr } { lv_name }| ) ) ).

    SET HANDLER on_toolbar       FOR lo_grid.
    SET HANDLER on_user_command  FOR lo_grid.
    SET HANDLER on_data_changed  FOR lo_grid.
    SET HANDLER on_hotspot_click FOR lo_grid.

    DATA(lw_layout)  = get_layout( ).
    DATA(lt_exclude) = get_exclude( ).

    lo_grid->set_table_for_first_display(
      EXPORTING
        is_variant                    = VALUE disvariant( report = sy-repid )
        i_default                     = abap_true
        i_save                        = 'A'
        is_layout                     = lw_layout
        it_toolbar_excluding          = lt_exclude
      CHANGING
        it_outtab                     = mt_data
        it_fieldcatalog               = lt_fcat
      EXCEPTIONS
        invalid_parameter_combination = 1
        program_error                 = 2
        too_many_lines                = 3
        OTHERS                        = 4 ).
    IF sy-subrc <> 0.
      lcl_util=>raise_sy_message( ).
      RETURN.
    ENDIF.

    finish_display( ).
  ENDMETHOD.

  METHOD on_toolbar.
    add_toolbar_button( EXPORTING iv_function = gc_fc_sel_all
                                  iv_icon     = icon_select_all
                                  io_object   = e_object ).
    add_toolbar_button( EXPORTING iv_function = gc_fc_des_all
                                  iv_icon     = icon_deselect_all
                                  io_object   = e_object ).
    add_toolbar_button( EXPORTING iv_function = gc_fc_post
                                  iv_icon     = icon_execute_object
                                  iv_text     = `Post Data`
                                  io_object   = e_object ).
    add_toolbar_button( EXPORTING iv_function = gc_fc_simu
                                  iv_icon     = icon_simulate
                                  iv_text     = `Simulate Data`
                                  io_object   = e_object ).
  ENDMETHOD.

  METHOD on_user_command.
    mo_grid->check_changed_data( ).

    CASE e_ucomm.
      WHEN gc_fc_post.
        IF mv_simulated = abap_false.
          MESSAGE 'Simulate first' TYPE 'S' DISPLAY LIKE 'E' ##NO_TEXT.
          RETURN.
        ENDIF.
        mv_test = abap_false.
        post( ).
      WHEN gc_fc_simu.
        mv_test = abap_true.
        post( ).
        mv_simulated = abap_true.
      WHEN gc_fc_sel_all.
        set_selection( abap_true ).
      WHEN gc_fc_des_all.
        set_selection( abap_false ).
      WHEN OTHERS.
        RETURN.
    ENDCASE.

    optimize_and_refresh( ).
  ENDMETHOD.

  METHOD on_data_changed.
    IF er_data_changed->mt_mod_cells IS NOT INITIAL.
      CLEAR mv_simulated.
    ENDIF.
  ENDMETHOD.

  METHOD on_hotspot_click.
    DATA lv_docno TYPE belnr_d.

    READ TABLE mt_data INTO DATA(lw_data) INDEX e_row_id-index.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    CASE e_column_id-fieldname.
      WHEN 'BELNR_AR' OR 'AUGBL'.
        lv_docno = COND #( WHEN e_column_id-fieldname = 'AUGBL'
                           THEN lw_data-augbl
                           ELSE lw_data-belnr_ar ).
        IF lv_docno IS INITIAL.
          RETURN.
        ENDIF.
        SET PARAMETER ID 'BLN' FIELD lv_docno.
        SET PARAMETER ID 'BUK' FIELD s_bukrs-low.
        SET PARAMETER ID 'GJR' FIELD lw_data-gjahr.
        CALL TRANSACTION gc_tcode_fi AND SKIP FIRST SCREEN.

      WHEN 'BELNR_AP'.
        lv_docno = lw_data-belnr_ap.
        IF lv_docno IS INITIAL.
          RETURN.
        ENDIF.
        SET PARAMETER ID 'RBN' FIELD lv_docno.
        SET PARAMETER ID 'GJR' FIELD lw_data-gjahr.
        CALL TRANSACTION gc_tcode_mm AND SKIP FIRST SCREEN.

      WHEN OTHERS.
        RETURN.
    ENDCASE.
  ENDMETHOD.

  METHOD set_selection.
    LOOP AT mt_data ASSIGNING FIELD-SYMBOL(<lf_data>) WHERE light = gc_st_open.
      <lf_data>-sel = iv_sel.
    ENDLOOP.
  ENDMETHOD.

  METHOD post.
    READ TABLE mt_data TRANSPORTING NO FIELDS WITH KEY sel = abap_true.
    IF sy-subrc <> 0.
      MESSAGE 'Choose rows' TYPE 'S' DISPLAY LIKE 'E' ##NO_TEXT.
      RETURN.
    ENDIF.

    LOOP AT mt_data ASSIGNING FIELD-SYMBOL(<lf_data>) WHERE sel = abap_true.

      CLEAR: <lf_data>-message,
             <lf_data>-belnr_ap,
             <lf_data>-belnr_ar.

      post_ap_invoice( CHANGING cw_claim = <lf_data> ).
      IF <lf_data>-belnr_ap IS INITIAL.
        <lf_data>-light  = gc_st_error.
        <lf_data>-status = icon_led_red.
        CONTINUE.
      ENDIF.

      post_ar_invoice( CHANGING cw_claim = <lf_data> ).
      IF <lf_data>-belnr_ar IS INITIAL.
        reverse_ap_invoice( CHANGING cw_claim = <lf_data> ).
        <lf_data>-light  = gc_st_error.
        <lf_data>-status = icon_led_red.
        CONTINUE.
      ENDIF.

      <lf_data>-light   = gc_st_realized.
      "test mode must stay visually distinct from a real posting
      <lf_data>-status  = COND #( WHEN mv_test = abap_true
                                  THEN icon_led_yellow
                                  ELSE icon_led_green ).

      <lf_data>-sel     =  COND #( WHEN mv_test = abap_true
                                   THEN abap_true
                                   ELSE abap_false ).

      <lf_data>-message = |AP { <lf_data>-belnr_ap } / AR { <lf_data>-belnr_ar } created successfully| ##NO_TEXT.

      <lf_data>-style   = COND #( WHEN mv_test = abap_false
                                  THEN lcl_util=>disable_cells( VALUE #( ( `SEL` ) ) ) ).
    ENDLOOP.

    IF mv_test = abap_true.
      MESSAGE s398(00) WITH 'Test run completed - no documents posted' ##NO_TEXT.
    ENDIF.
  ENDMETHOD.

  METHOD post_ap_invoice.
    DATA:
      lt_item   TYPE STANDARD TABLE OF bapi_incinv_create_item,
      lt_return TYPE bapiret2_t,
      lv_belnr  TYPE belnr_d,
      lv_gjahr  TYPE gjahr.

    DATA(lv_amount) = lcl_util=>to_external( cw_claim-netwr ).

    DATA(lw_header) = VALUE bapi_incinv_create_header(
      invoice_ind  = abap_true
      doc_type     = lcl_config=>doc_type_ap( )
      doc_date     = p_bldat
      pstng_date   = p_budat
      comp_code    = gv_bukrs
      currency     = gc_curr
      gross_amount = lv_amount
      calc_tax_ind = abap_false
      ref_doc_no   = p_xblnr
      alloc_nmbr   = cw_claim-zuonr
      header_txt   = 'Promotion expense' ) ##NO_TEXT.

    lt_item = VALUE #( ( invoice_doc_item = '000001'
                         po_number        = cw_claim-ebeln
                         po_item          = cw_claim-ebelp
                         item_amount      = lv_amount
                         tax_code         = gc_tax_code ) ).

    CALL FUNCTION 'BAPI_INCOMINGINVOICE_CREATE1'
      EXPORTING
        headerdata       = lw_header
      IMPORTING
        invoicedocnumber = lv_belnr
        fiscalyear       = lv_gjahr
      TABLES
        itemdata         = lt_item
        return           = lt_return.

    IF lcl_util=>has_bapi_error( lt_return ) = abap_true
      OR lv_belnr IS INITIAL.

      CALL FUNCTION 'BAPI_TRANSACTION_ROLLBACK'.

      cw_claim-message = 'Vendor Invoice failed to create' ##NO_TEXT.
      RETURN.
    ENDIF.

    IF mv_test = abap_true.
      CALL FUNCTION 'BAPI_TRANSACTION_ROLLBACK'.
      cw_claim-belnr_ap = gc_simulated.
      cw_claim-gjahr    = lv_gjahr.
      RETURN.
    ENDIF.

    CALL FUNCTION 'BAPI_TRANSACTION_COMMIT'
      EXPORTING
        wait = abap_true.

    cw_claim-belnr_ap = lv_belnr.
    cw_claim-gjahr    = lv_gjahr.
  ENDMETHOD.

  METHOD post_ar_invoice.
    CONSTANTS:
      lc_item_ap TYPE posnr_acc VALUE '0000000001',
      lc_item_ar TYPE posnr_acc VALUE '0000000002'.

    DATA:
      lt_payable    TYPE STANDARD TABLE OF bapiacap09 WITH EMPTY KEY,
      lt_receivable TYPE STANDARD TABLE OF bapiacar09 WITH EMPTY KEY,
      lt_currency   TYPE STANDARD TABLE OF bapiaccr09 WITH EMPTY KEY,
      lt_ext2       TYPE STANDARD TABLE OF bapiparex WITH EMPTY KEY,
      lt_return     TYPE bapiret2_t,
      lv_obj_key    TYPE bapiache09-obj_key.

    "Customer determination stays explicit - OI-11 is a Finance decision
    IF cw_claim-partner IS INITIAL.
      cw_claim-message = 'Claimable AR customer not determined' ##NO_TEXT.
      RETURN.
    ENDIF.

    DATA(lv_amount) = lcl_util=>to_external( cw_claim-netwr ).

    DATA(lw_header) = VALUE bapiache09(
      username   = sy-uname
      comp_code  = gv_bukrs
      doc_date   = p_bldat
      pstng_date = p_budat
      doc_type   = lcl_config=>doc_type_ar( )
      ref_doc_no = p_xblnr
      header_txt = 'Promotion claim' ) ##NO_TEXT.

    "Debit AP - same vendor as step 1
    lt_payable = VALUE #( ( itemno_acc = lc_item_ap
                            vendor_no  = cw_claim-lifnr
                            alloc_nmbr = cw_claim-zuonr
                            item_text  = 'Promotion expense claim'
                            profit_ctr = cw_claim-prctr
                            bus_area   = cw_claim-gsber ) ) ##NO_TEXT.

    "Credit claimable AR
    lt_receivable = VALUE #( ( itemno_acc = lc_item_ar
                               customer   = cw_claim-partner
                               alloc_nmbr = cw_claim-zuonr
                               item_text  = 'Claimable promotion expense'
                               profit_ctr = cw_claim-prctr
                               bus_area   = cw_claim-gsber ) ) ##NO_TEXT.

    "Invoice reference (REBZG) prepared for EXTENSION2 - deliberately not
    "handed to the BAPI yet, the receiving BAdI/BTE is still open on FI side
    lt_ext2 = VALUE #( structure = gc_ext_struc
                       ( valuepart2 = 'CLEAR_REBZG' valuepart1 = lc_item_ap )
                       ( valuepart2 = 'CLEAR_REBZG' valuepart1 = lc_item_ar ) ) ##NO_TEXT ##NEEDED.

    lt_currency = VALUE #( currency = gc_curr
                           ( itemno_acc = lc_item_ap
                             amt_doccur = lv_amount )
                           ( itemno_acc = lc_item_ar
                             amt_doccur = lv_amount * -1 ) ).

    CALL FUNCTION 'BAPI_ACC_DOCUMENT_CHECK'
      EXPORTING
        documentheader    = lw_header
      TABLES
        accountreceivable = lt_receivable
        accountpayable    = lt_payable
        currencyamount    = lt_currency
        return            = lt_return.

    IF lcl_util=>has_bapi_error( lt_return ) = abap_true.
      cw_claim-message = lcl_util=>bapi_error( lt_return ).
      IF cw_claim-message IS INITIAL.
        cw_claim-message = 'Claimable AR check failed' ##NO_TEXT.
      ENDIF.
      RETURN.
    ENDIF.

    IF mv_test = abap_true.
      cw_claim-belnr_ar = gc_simulated.
      RETURN.
    ENDIF.

    CLEAR lt_return.
    CALL FUNCTION 'BAPI_ACC_DOCUMENT_POST'
      EXPORTING
        documentheader    = lw_header
      IMPORTING
        obj_key           = lv_obj_key
      TABLES
        accountreceivable = lt_receivable
        accountpayable    = lt_payable
        currencyamount    = lt_currency
        return            = lt_return.

    IF lcl_util=>has_bapi_error( lt_return ) = abap_true
      OR lv_obj_key IS INITIAL.

      CALL FUNCTION 'BAPI_TRANSACTION_ROLLBACK'.

      cw_claim-message = lcl_util=>bapi_error( lt_return ).
      IF cw_claim-message IS INITIAL.
        cw_claim-message = 'Claimable AR posting failed' ##NO_TEXT.
      ENDIF.
      RETURN.
    ENDIF.

    CALL FUNCTION 'BAPI_TRANSACTION_COMMIT'
      EXPORTING
        wait = abap_true.

    cw_claim-belnr_ar = lv_obj_key(10).
  ENDMETHOD.

  METHOD reverse_ap_invoice.
    DATA:
      lt_return TYPE bapiret2_t,
      lv_rev    TYPE belnr_d,
      lv_ryear  TYPE gjahr.

    IF mv_test = abap_true OR cw_claim-belnr_ap = gc_simulated.
      RETURN.
    ENDIF.

    CALL FUNCTION 'BAPI_INCOMINGINVOICE_CANCEL'
      EXPORTING
        invoicedocnumber         = cw_claim-belnr_ap
        fiscalyear               = cw_claim-gjahr
        reasonreversal           = gc_reason_rev
        postingdate              = p_budat
      IMPORTING
        invoicedocnumber_reverse = lv_rev
        fiscalyear_reverse       = lv_ryear
      TABLES
        return                   = lt_return.

    IF lcl_util=>has_bapi_error( lt_return ) = abap_true.
      CALL FUNCTION 'BAPI_TRANSACTION_ROLLBACK'.
      cw_claim-message =
        |CRITICAL: AP invoice { cw_claim-belnr_ap } could not be reversed| ##NO_TEXT.
      RETURN.
    ENDIF.

    CALL FUNCTION 'BAPI_TRANSACTION_COMMIT'
      EXPORTING
        wait = abap_true.
  ENDMETHOD.
ENDCLASS.

CLASS lcl_mode_b IMPLEMENTATION.
  METHOD has_data.
    rv_filled = xsdbool( mt_claim IS NOT INITIAL ).
  ENDMETHOD.

  METHOD build_zuonr_range.
    rt_range = s_zuonr[].

    IF s_pebel[] IS INITIAL.
      RETURN.
    ENDIF.

    SELECT @imphs_c_sign-including AS sign,
           @imphs_c_option-equal   AS option,
           concat( ebeln, ebelp )  AS low
      FROM ekpo
      WHERE ebeln IN @s_pebel
        AND ebelp IN @s_pebep
      INTO TABLE @DATA(lt_ekpo).
    IF sy-subrc = 0.
      rt_range = CORRESPONDING #( lt_ekpo ).
    ENDIF.
  ENDMETHOD.

  METHOD select.
    CLEAR mt_claim.

    DATA(lr_zuonr) = build_zuonr_range( ).

    "Guard: a PO restriction that resolves to nothing must not widen the result
    IF s_pebel[] IS NOT INITIAL AND lr_zuonr IS INITIAL.
      MESSAGE s398(00) WITH 'No PO item found for the given purchase order' ##NO_TEXT.
      RETURN.
    ENDIF.

    "Claimable AR = open customer item carrying the Assignment, restricted
    "to the configured AR document type and the creating transaction
    WITH
      +open_item AS (
        SELECT a~bukrs, a~belnr, a~gjahr, a~buzei, a~kunnr, a~zuonr,
               a~wrbtr, a~waers, a~hkont, a~augbl, b~name1, a~prctr,
               @icon_led_yellow            AS status,
               substring( a~zuonr, 1, 10 ) AS ebeln,
               substring( a~zuonr, 11, 5 ) AS ebelp
          FROM bsid_view AS a
          INNER JOIN kna1 AS b ON a~kunnr = b~kunnr
          INNER JOIN bkpf AS c ON a~bukrs = c~bukrs
                              AND a~belnr = c~belnr
                              AND a~gjahr = c~gjahr
          WHERE a~bukrs =  @gv_bukrs
            AND a~gjahr =  @p_gjahr
            AND a~belnr IN @s_belnr
            AND a~kunnr IN @s_kunnr
            AND a~budat IN @s_arbud
            AND a~zuonr IN @lr_zuonr
            AND a~zuonr <> @space
            AND a~shkzg =  @gc_credit
            AND a~umskz =  @space
            AND c~blart =  @gv_doc_type_ar
            AND c~tcode =  @sy-tcode ),

      +po AS (
        SELECT a~ebeln, a~ebelp
          FROM ekpo AS a
          INNER JOIN +open_item AS b ON a~ebeln = b~ebeln
                                    AND a~ebelp = b~ebelp
          WHERE a~ebeln IN @s_pebel
            AND a~ebelp IN @s_pebep )

      SELECT *
        FROM +open_item AS a
        LEFT JOIN +po AS b ON a~ebeln = b~ebeln
                          AND a~ebelp = b~ebelp
        INTO CORRESPONDING FIELDS OF TABLE @mt_claim.

    IF mt_claim IS INITIAL.
      MESSAGE s398(00) WITH 'Clearing AR not found' ##NO_TEXT.
    ENDIF.
  ENDMETHOD.

  METHOD build_fieldcat.
    CALL FUNCTION 'LVC_FIELDCATALOG_MERGE'
      EXPORTING
        i_structure_name       = 'ZST_FI_CLEAR_OUTSTANDING'
        i_bypassing_buffer     = abap_true
      CHANGING
        ct_fieldcat            = rt_fcat
      EXCEPTIONS
        inconsistent_interface = 1
        program_error          = 2
        OTHERS                 = 3.
    IF sy-subrc <> 0.
      lcl_util=>raise_sy_message( ).
      RETURN.
    ENDIF.

    LOOP AT rt_fcat ASSIGNING FIELD-SYMBOL(<lf_fcat>).
      CASE <lf_fcat>-fieldname.
        WHEN 'SEL'.
          lcl_util=>set_fcat( EXPORTING iv_label     = `Checkbox`
                                        iv_edit      = abap_true
                                        iv_checkbox  = abap_true
                                        iv_outputlen = 3
                              CHANGING  cw_fcat      = <lf_fcat> ).
        WHEN 'STATUS'.
          lcl_util=>set_fcat( EXPORTING iv_label = `Indicator`
                              CHANGING  cw_fcat  = <lf_fcat> ).
        WHEN 'BELNR'.
          lcl_util=>set_fcat( EXPORTING iv_label   = `Claimable Document`
                                        iv_hotspot = abap_true
                              CHANGING  cw_fcat    = <lf_fcat> ).
        WHEN 'BELNR_OUTS'.
          lcl_util=>set_fcat( EXPORTING iv_label = `Doc Number Outstanding`
                                        iv_edit  = abap_true
                                        iv_f4    = abap_true
                              CHANGING  cw_fcat  = <lf_fcat> ).
        WHEN 'GJAHR_OUTS'.
          lcl_util=>set_fcat( EXPORTING iv_label = `Fiscal Year Outstanding`
                                        iv_edit  = abap_true
                              CHANGING  cw_fcat  = <lf_fcat> ).
        WHEN 'AMT_OUTS'.
          lcl_util=>set_fcat( EXPORTING iv_label = `Amount Outstanding`
                              CHANGING  cw_fcat  = <lf_fcat> ).
        WHEN 'AMT_REMAINING'.
          lcl_util=>set_fcat( EXPORTING iv_label = `Amount Remaining`
                              CHANGING  cw_fcat  = <lf_fcat> ).
        WHEN OTHERS.
          "keep the DDIC labels
      ENDCASE.
    ENDLOOP.
  ENDMETHOD.

  METHOD display.
    DATA(lt_fcat) = build_fieldcat( ).

    DATA(lo_grid) = create_grid(
      EXPORTING
        iv_title       = `AR Clearing`
        it_info        = VALUE string_table( ( |Company Code: { gv_bukrs }| ) )
        iv_enter_event = abap_true
        it_f4          = VALUE lvc_t_f4( ( fieldname  = 'BELNR_OUTS'
                                           register   = abap_true
                                           chngeafter = abap_true ) ) ).

    SET HANDLER on_toolbar       FOR lo_grid.
    SET HANDLER on_user_command  FOR lo_grid.
    SET HANDLER on_data_changed  FOR lo_grid.
    SET HANDLER on_value_request FOR lo_grid.
    SET HANDLER on_hotspot_click FOR lo_grid.

    DATA(lw_layout)  = get_layout( ).
    DATA(lt_exclude) = get_exclude( ).

    lo_grid->set_table_for_first_display(
      EXPORTING
        i_bypassing_buffer            = abap_true
        is_variant                    = VALUE disvariant( report = sy-repid )
        i_default                     = abap_true
        i_save                        = 'A'
        is_layout                     = lw_layout
        it_toolbar_excluding          = lt_exclude
      CHANGING
        it_outtab                     = mt_claim
        it_fieldcatalog               = lt_fcat
      EXCEPTIONS
        invalid_parameter_combination = 1
        program_error                 = 2
        too_many_lines                = 3
        OTHERS                        = 4 ).
    IF sy-subrc <> 0.
      lcl_util=>raise_sy_message( ).
      RETURN.
    ENDIF.

    finish_display( ).
  ENDMETHOD.

  METHOD on_toolbar.
    add_toolbar_button( EXPORTING iv_function = gc_fc_sel_all
                                  iv_icon     = icon_select_all
                                  io_object   = e_object ).
    add_toolbar_button( EXPORTING iv_function = gc_fc_des_all
                                  iv_icon     = icon_deselect_all
                                  io_object   = e_object ).
    add_toolbar_button( EXPORTING iv_function = gc_fc_post
                                  iv_icon     = icon_execute_object
                                  iv_text     = `Start Clearing`
                                  io_object   = e_object ).
    add_toolbar_button( EXPORTING iv_function = gc_fc_simu
                                  iv_icon     = icon_simulate
                                  iv_text     = `Simulate Data`
                                  io_object   = e_object ).
  ENDMETHOD.

  METHOD on_user_command.
    mo_grid->check_changed_data( IMPORTING e_valid = DATA(lv_valid) ).
    IF lv_valid = abap_false.
      MESSAGE 'There are invalid entries' TYPE 'S' DISPLAY LIKE 'E' ##NO_TEXT.
      RETURN.
    ENDIF.

    CASE e_ucomm.
      WHEN gc_fc_post.
        IF mv_simulated = abap_false.
          MESSAGE 'Simulate first' TYPE 'S' DISPLAY LIKE 'E' ##NO_TEXT.
          RETURN.
        ENDIF.
        CLEAR mv_simulated.
        post_clearing( ).
      WHEN gc_fc_simu.
        simulate( ).
        mv_simulated = abap_true.
      WHEN gc_fc_sel_all.
        set_selection( abap_true ).
      WHEN gc_fc_des_all.
        set_selection( abap_false ).
      WHEN OTHERS.
        RETURN.
    ENDCASE.

    optimize_and_refresh( ).
  ENDMETHOD.

  METHOD set_selection.
    LOOP AT mt_claim ASSIGNING FIELD-SYMBOL(<lf_claim>).
      <lf_claim>-sel = iv_sel.
    ENDLOOP.
    CLEAR mv_simulated.
  ENDMETHOD.

  METHOD on_data_changed.
    IF er_data_changed->mt_mod_cells IS NOT INITIAL.
      CLEAR mv_simulated.
    ENDIF.
  ENDMETHOD.

  METHOD on_hotspot_click.
    READ TABLE mt_claim INTO DATA(lw_claim) INDEX e_row_id-index.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    CASE e_column_id-fieldname.
      WHEN 'BELNR'.
        SET PARAMETER ID 'BLN' FIELD lw_claim-belnr.
        SET PARAMETER ID 'BUK' FIELD lw_claim-bukrs.
        SET PARAMETER ID 'GJR' FIELD lw_claim-gjahr.
        CALL TRANSACTION gc_tcode_fi AND SKIP FIRST SCREEN.
      WHEN OTHERS.
        RETURN.
    ENDCASE.
  ENDMETHOD.

  METHOD open_items_for_f4.
    SELECT a~bukrs, a~belnr, a~gjahr, a~kunnr, a~wrbtr, a~waers
      FROM bsid_view AS a
      WHERE a~bukrs = @iw_claim-bukrs
*        AND a~kunnr = @iw_claim-kunnr
        AND a~shkzg = @gc_debit
        AND a~waers = @gc_curr
      ORDER BY a~bukrs, a~belnr, a~gjahr
      INTO TABLE @rt_items.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    DATA(lt_item) = rt_items.
    IF lt_item IS INITIAL.
      RETURN.
    ENDIF.

    SELECT SUM( a~wrbtr ) AS sum_wrbtr, b~belnr, b~gjahr, b~bukrs,  b~kunnr
      FROM bseg AS a
      INNER JOIN @lt_item AS b ON a~rebzg = b~belnr
                              AND a~rebzj = b~gjahr
      WHERE a~augbl IS INITIAL
        AND EXISTS ( SELECT @abap_true
                       FROM bseg AS c
                      WHERE c~bukrs = a~bukrs
                        AND c~augbl = a~belnr )
      GROUP BY b~belnr, b~gjahr, b~bukrs, b~kunnr
      INTO TABLE @DATA(lt_consumed) ##DB_FEATURE_MODE[ITABS_IN_FROM_CLAUSE].
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    LOOP AT lt_consumed INTO DATA(lw_consumed).
      READ TABLE rt_items ASSIGNING FIELD-SYMBOL(<lf_item>)
        WITH KEY bukrs = lw_consumed-bukrs
                 belnr = lw_consumed-belnr
                 gjahr = lw_consumed-gjahr
                 BINARY SEARCH.
      IF sy-subrc = 0.
        <lf_item>-wrbtr -= lw_consumed-sum_wrbtr.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD on_value_request.
    DATA:
      lt_return   TYPE STANDARD TABLE OF ddshretval WITH EMPTY KEY,
      lt_dynfield TYPE STANDARD TABLE OF dselc WITH EMPTY KEY.

    FIELD-SYMBOLS <lf_modi> TYPE lvc_t_modi.

    READ TABLE mt_claim INTO DATA(lw_claim) INDEX es_row_no-row_id.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    DATA(lt_open_item) = open_items_for_f4( lw_claim ).

    lt_dynfield = VALUE #( ( fldname = 'BELNR' dyfldname = 'BELNR' )
                           ( fldname = 'GJAHR' dyfldname = 'GJAHR' )
                           ( fldname = 'KUNNR' dyfldname = 'KUNNR' )
                         ).

    CALL FUNCTION 'F4IF_INT_TABLE_VALUE_REQUEST'
      EXPORTING
        ddic_structure   = 'ZST_FI_SEARCH_HELP_AR'
        retfield         = 'BELNR'
        value_org        = 'S'
        callback_program = sy-repid
        callback_form    = 'F4CALLBACK'
      TABLES
        value_tab        = lt_open_item
        return_tab       = lt_return
        dynpfld_mapping  = lt_dynfield
      EXCEPTIONS
        parameter_error  = 1
        no_values_found  = 2
        OTHERS           = 3.

    er_event_data->m_event_handled = abap_true.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    READ TABLE lt_return INTO DATA(lw_return) INDEX 1.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    ASSIGN er_event_data->m_data->* TO <lf_modi>.
    IF <lf_modi> IS NOT ASSIGNED.
      RETURN.
    ENDIF.

    <lf_modi> = VALUE #( BASE <lf_modi>
                         ( row_id    = es_row_no-row_id
                           fieldname = e_fieldname
                           value     = lw_return-fieldval ) ).

    READ TABLE lt_return INTO DATA(lw_year) INDEX 2.
    IF sy-subrc = 0.
      <lf_modi> = VALUE #( BASE <lf_modi>
                           ( row_id    = es_row_no-row_id
                             fieldname = 'GJAHR_OUTS'
                             value     = lw_year-fieldval ) ).
    ENDIF.

    READ TABLE lt_return INTO lw_year INDEX 3.
    IF sy-subrc = 0.
      <lf_modi> = VALUE #( BASE <lf_modi>
                           ( row_id    = es_row_no-row_id
                             fieldname = 'KUNNR_OUTS'
                             value     = lw_year-fieldval ) ).
    ENDIF.

    CLEAR mv_simulated.
  ENDMETHOD.

  METHOD read_outstanding.
    CLEAR mt_outst.

    DATA(lt_claim) = mt_claim.
    IF lt_claim IS INITIAL.
      RETURN.
    ENDIF.

    SELECT a~bukrs,
           a~belnr,
           a~gjahr,
           a~buzei,
           a~prctr,
           a~gsber,
           a~kunnr,
           a~xblnr,
           a~wrbtr
      FROM bsid_view AS a
      INNER JOIN @lt_claim AS b ON a~bukrs = b~bukrs
                               AND a~belnr = b~belnr_outs
                               AND a~gjahr = b~gjahr_outs
      WHERE b~sel        =  @abap_true
        AND b~belnr_outs <> @space
        AND a~shkzg      =  @gc_debit
        AND a~kunnr      IN @s_kunnr
      ORDER BY a~bukrs, a~belnr, a~gjahr
      INTO CORRESPONDING FIELDS OF TABLE @mt_outst ##DB_FEATURE_MODE[ITABS_IN_FROM_CLAUSE].
    IF mt_outst IS INITIAL.
      RETURN.
    ENDIF.

    "Reduce the balance by amounts already consumed by other clearings
    DATA(lt_outst) = mt_outst.
    SELECT SUM( a~wrbtr ) AS sum_wrbtr, b~belnr, b~gjahr, b~bukrs
      FROM bseg AS a
      INNER JOIN @lt_outst AS b ON a~rebzg = b~belnr
                               AND a~rebzj = b~gjahr
      WHERE a~augbl IS INITIAL
        AND EXISTS ( SELECT @abap_true
                       FROM bseg AS c
                      WHERE c~bukrs = a~bukrs
                        AND c~augbl = a~belnr )
      GROUP BY b~belnr, b~gjahr, b~bukrs
      INTO TABLE @DATA(lt_consumed) ##DB_FEATURE_MODE[ITABS_IN_FROM_CLAUSE].
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    LOOP AT lt_consumed INTO DATA(lw_consumed).
      READ TABLE mt_outst ASSIGNING FIELD-SYMBOL(<lf_outst>)
        WITH KEY bukrs = lw_consumed-bukrs
                 belnr = lw_consumed-belnr
                 gjahr = lw_consumed-gjahr
                 BINARY SEARCH.
      IF sy-subrc = 0.
        <lf_outst>-wrbtr -= lw_consumed-sum_wrbtr.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD simulate.
    READ TABLE mt_claim TRANSPORTING NO FIELDS WITH KEY sel = abap_true.
    IF sy-subrc <> 0.
      MESSAGE 'Select claimable AR' TYPE 'S' DISPLAY LIKE 'E' ##NO_TEXT.
      RETURN.
    ENDIF.

    read_outstanding( ).

    LOOP AT mt_claim ASSIGNING FIELD-SYMBOL(<lf_claim>).
      IF <lf_claim>-sel = abap_false.
        <lf_claim>-status = icon_led_yellow.
        CLEAR: <lf_claim>-belnr_outs,
               <lf_claim>-gjahr_outs,
               <lf_claim>-amt_outs,
               <lf_claim>-amt_remaining,
               <lf_claim>-message.
        CONTINUE.
      ENDIF.

      IF <lf_claim>-belnr_outs IS INITIAL
        OR <lf_claim>-gjahr_outs IS INITIAL.
        <lf_claim>-message = |Skip: no outstanding AR assigned to claim | &&
                             |{ <lf_claim>-belnr }/{ <lf_claim>-gjahr } | &&
                             |customer { <lf_claim>-kunnr }| ##NO_TEXT.
        <lf_claim>-status  = icon_led_red.
        CONTINUE.
      ENDIF.

      READ TABLE mt_outst ASSIGNING FIELD-SYMBOL(<lf_outst>)
        WITH KEY bukrs = <lf_claim>-bukrs
                 belnr = <lf_claim>-belnr_outs
                 gjahr = <lf_claim>-gjahr_outs
                 BINARY SEARCH.
      IF sy-subrc <> 0.
        <lf_claim>-message = |Skip: outstanding AR { <lf_claim>-belnr_outs } not found| ##NO_TEXT.
        <lf_claim>-status  = icon_led_red.
        CONTINUE.
      ENDIF.

*      "Defect fix: the customer of the outstanding item must match the claim
*      IF <lf_outst>-kunnr <> <lf_claim>-kunnr.
*        <lf_claim>-message = |Skip: outstanding AR { <lf_claim>-belnr_outs } belongs to | &&
*                             |customer { <lf_outst>-kunnr }, claim { <lf_claim>-belnr } | &&
*                             |to customer { <lf_claim>-kunnr }| ##NO_TEXT.
*        <lf_claim>-status  = icon_led_red.
*        CONTINUE.
*      ENDIF.

      IF <lf_outst>-wrbtr < <lf_claim>-wrbtr.
        <lf_claim>-message = |Skip: outstanding AR { <lf_claim>-belnr_outs } balance | &&
                             |{ <lf_outst>-wrbtr } is lower than claim { <lf_claim>-belnr } | &&
                             |amount { <lf_claim>-wrbtr }| ##NO_TEXT.
        <lf_claim>-status  = icon_led_red.
        CONTINUE.
      ENDIF.

      <lf_outst>-remaining = COND #( WHEN <lf_outst>-remaining <> 0
                                     THEN <lf_outst>-remaining - <lf_claim>-wrbtr
                                     ELSE <lf_outst>-wrbtr - <lf_claim>-wrbtr ).

      <lf_claim>-amt_outs      = <lf_outst>-wrbtr.
      <lf_claim>-amt_remaining = <lf_outst>-remaining.

      IF <lf_outst>-remaining < 0.
        <lf_claim>-message = |Skip: outstanding AR { <lf_claim>-belnr_outs } remaining | &&
                             |{ <lf_outst>-remaining } is lower than claim { <lf_claim>-belnr } | &&
                             |amount { <lf_claim>-wrbtr }| ##NO_TEXT.
        <lf_claim>-status  = icon_led_red.
        CONTINUE.
      ENDIF.

      <lf_claim>-status = icon_led_green.
      CLEAR <lf_claim>-message.
    ENDLOOP.
  ENDMETHOD.

  METHOD post_clearing.
    DATA: lv_posted TYPE i,
          lv_failed TYPE i.

    READ TABLE mt_claim TRANSPORTING NO FIELDS
      WITH KEY sel    = abap_true
               status = icon_led_green.
    IF sy-subrc <> 0.
      MESSAGE 'Select valid claimable AR' TYPE 'S' DISPLAY LIKE 'E' ##NO_TEXT.
      RETURN.
    ENDIF.

    LOOP AT mt_claim ASSIGNING FIELD-SYMBOL(<lf_claim>)
         WHERE sel    = abap_true
           AND status = icon_led_green.

      READ TABLE mt_outst INTO DATA(lw_outst)
        WITH KEY bukrs = <lf_claim>-bukrs
                 belnr = <lf_claim>-belnr_outs
                 gjahr = <lf_claim>-gjahr_outs
                 BINARY SEARCH.
      IF sy-subrc <> 0.
        <lf_claim>-status  = icon_led_red.
        <lf_claim>-message = |Skip: outstanding AR { <lf_claim>-belnr_outs } not found| ##NO_TEXT.
        lv_failed += 1.
        CONTINUE.
      ENDIF.

      post_single( EXPORTING iw_outst = lw_outst
                   CHANGING  cw_claim = <lf_claim> ).

      IF <lf_claim>-augbl IS INITIAL.
        lv_failed += 1.
      ELSE.
        lv_posted += 1.
      ENDIF.
    ENDLOOP.

    DATA(lv_text) = |{ lv_posted } document(s) cleared, { lv_failed } failed| ##NO_TEXT.
    IF lv_failed > 0.
      MESSAGE lv_text TYPE 'S' DISPLAY LIKE 'E'.
    ELSE.
      MESSAGE lv_text TYPE 'S'.
    ENDIF.
  ENDMETHOD.

  METHOD post_single.
    CONSTANTS:
      lc_newbs_credit TYPE c LENGTH 2 VALUE '17',
      lc_stype_post   TYPE c LENGTH 1 VALUE 'P',
      lc_stype_head   TYPE c LENGTH 1 VALUE 'K',
      lc_count        TYPE i          VALUE 1,
      lc_func_clear   TYPE c LENGTH 1 VALUE 'C',
      lc_mode_nodisp  TYPE c LENGTH 1 VALUE 'N',
      lc_update_sync  TYPE c LENGTH 1 VALUE 'S'.

    DATA:
      lv_subrc      TYPE sy-subrc,
      lv_msgid      TYPE sy-msgid,
      lv_msgno      TYPE sy-msgno,
      lv_msgty      TYPE sy-msgty,
      lv_msgv1      TYPE sy-msgv1,
      lv_msgv2      TYPE sy-msgv2,
      lv_msgv3      TYPE sy-msgv3,
      lv_msgv4      TYPE sy-msgv4,
      lv_message    TYPE bapiret2-message,
      lv_textformat TYPE bapitga-textformat,
      lv_amount     TYPE bdc_fval,
      lt_blntab     TYPE epic_t_ebr_blntab,
      lt_fttax      TYPE feb_t_fttax,
      lt_ftclear    TYPE feb_t_ftclear,
      lt_ftpost     TYPE feb_t_ftpost.

    lt_ftclear = VALUE #(
      ( agkoa  = gc_customer
        agkon  = |{ cw_claim-kunnr ALPHA = IN }|
        agbuk  = gv_bukrs
        xnops  = abap_true
        selfd  = 'BELNR'
        selvon = |{ cw_claim-belnr ALPHA = IN }{ cw_claim-gjahr ALPHA = IN }{ cw_claim-buzei ALPHA = IN }|
        selbis = |{ cw_claim-belnr ALPHA = IN }{ cw_claim-gjahr ALPHA = IN }{ cw_claim-buzei ALPHA = IN }| ) ).

    IF cw_claim-wrbtr <> cw_claim-amt_outs.
      "Partial payment - residual item on the outstanding receivable
      DATA(lv_profit_center) = |{ iw_outst-bukrs(3) }{ iw_outst-gsber }|.

      WRITE cw_claim-wrbtr TO lv_amount
        LEFT-JUSTIFIED NO-GROUPING CURRENCY cw_claim-waers.

      add_ftpost( EXPORTING iv_stype  = lc_stype_post
                            iv_count  = lc_count
                            iv_fnam   = 'RF05A-NEWBS'
                            iv_fval   = lc_newbs_credit
                  CHANGING  ct_ftpost = lt_ftpost ).
      add_ftpost( EXPORTING iv_stype  = lc_stype_post
                            iv_count  = lc_count
                            iv_fnam   = 'RF05A-NEWKO'
                            iv_fval   = cw_claim-kunnr_outs
                  CHANGING  ct_ftpost = lt_ftpost ).
      add_ftpost( EXPORTING iv_stype  = lc_stype_post
                            iv_count  = lc_count
                            iv_fnam   = 'BSEG-WRBTR'
                            iv_fval   = lv_amount
                  CHANGING  ct_ftpost = lt_ftpost ).
      add_ftpost( EXPORTING iv_stype  = lc_stype_post
                            iv_count  = lc_count
                            iv_fnam   = 'BSEG-REBZG'
                            iv_fval   = iw_outst-belnr
                  CHANGING  ct_ftpost = lt_ftpost ).
      add_ftpost( EXPORTING iv_stype  = lc_stype_post
                            iv_count  = lc_count
                            iv_fnam   = 'BSEG-REBZJ'
                            iv_fval   = iw_outst-gjahr
                  CHANGING  ct_ftpost = lt_ftpost ).
      add_ftpost( EXPORTING iv_stype  = lc_stype_post
                            iv_count  = lc_count
                            iv_fnam   = 'BSEG-PRCTR'
                            iv_fval   = lv_profit_center
                  CHANGING  ct_ftpost = lt_ftpost ).
      add_ftpost( EXPORTING iv_stype  = lc_stype_post
                            iv_count  = lc_count
                            iv_fnam   = 'BSEG-GSBER'
                            iv_fval   = iw_outst-gsber
                  CHANGING  ct_ftpost = lt_ftpost ).
    ELSE.
      "Full clearing - add the outstanding receivable to the clearing stack
      lt_ftclear = VALUE #( BASE lt_ftclear
        ( agkoa  = gc_customer
          agkon  = |{ cw_claim-kunnr ALPHA = IN }|
          agbuk  = gv_bukrs
          xnops  = abap_true
          selfd  = 'BELNR'
          selvon = |{ iw_outst-belnr ALPHA = IN }{ iw_outst-gjahr ALPHA = IN }{ iw_outst-buzei ALPHA = IN }|
          selbis = |{ iw_outst-belnr ALPHA = IN }{ iw_outst-gjahr ALPHA = IN }{ iw_outst-buzei ALPHA = IN }| ) ).
    ENDIF.

    DATA(lv_date)  = |{ p_clrdt DATE = USER }|.
    DATA(lv_bktxt) = |Clr Promotion claim| ##NO_TEXT.

    add_ftpost( EXPORTING iv_stype  = lc_stype_head
                          iv_count  = lc_count
                          iv_fnam   = 'BKPF-BUKRS'
                          iv_fval   = gv_bukrs
                CHANGING  ct_ftpost = lt_ftpost ).
    add_ftpost( EXPORTING iv_stype  = lc_stype_head
                          iv_count  = lc_count
                          iv_fnam   = 'BKPF-BLART'
                          iv_fval   = lcl_config=>doc_type_clearing( )
                CHANGING  ct_ftpost = lt_ftpost ).
    add_ftpost( EXPORTING iv_stype  = lc_stype_head
                          iv_count  = lc_count
                          iv_fnam   = 'BKPF-BLDAT'
                          iv_fval   = lv_date
                CHANGING  ct_ftpost = lt_ftpost ).
    add_ftpost( EXPORTING iv_stype  = lc_stype_head
                          iv_count  = lc_count
                          iv_fnam   = 'BKPF-BUDAT'
                          iv_fval   = lv_date
                CHANGING  ct_ftpost = lt_ftpost ).
    add_ftpost( EXPORTING iv_stype  = lc_stype_head
                          iv_count  = lc_count
                          iv_fnam   = 'BKPF-WAERS'
                          iv_fval   = gc_curr
                CHANGING  ct_ftpost = lt_ftpost ).
    add_ftpost( EXPORTING iv_stype  = lc_stype_head
                          iv_count  = lc_count
                          iv_fnam   = 'BKPF-XBLNR'
                          iv_fval   = cw_claim-zuonr
                CHANGING  ct_ftpost = lt_ftpost ).
    add_ftpost( EXPORTING iv_stype  = lc_stype_head
                          iv_count  = lc_count
                          iv_fnam   = 'BKPF-BKTXT'
                          iv_fval   = lv_bktxt
                CHANGING  ct_ftpost = lt_ftpost ).

    CALL FUNCTION 'ZPOSTING_INTERFACE_START'
      EXPORTING
        i_function         = lc_func_clear
        i_mode             = lc_mode_nodisp
*       i_mode             = 'A'
        i_update           = lc_update_sync
        i_client           = sy-mandt
        i_user             = sy-uname
      EXCEPTIONS
        client_incorrect   = 1
        function_invalid   = 2
        group_name_missing = 3
        mode_invalid       = 4
        update_invalid     = 5
        OTHERS             = 6.
    IF sy-subrc <> 0.
      cw_claim-status  = icon_led_red.
      cw_claim-message = |Skip: posting interface could not be started for | &&
                         |claim { cw_claim-belnr }, subrc { sy-subrc }| ##NO_TEXT.
      RETURN.
    ENDIF.

    CALL FUNCTION 'ZPOSTING_INTERFACE_CLEARING'
      EXPORTING
        i_auglv                    = gc_auglv
        i_tcode                    = gc_tcode_clr
        i_sgfunct                  = gc_sgfunc
      IMPORTING
        e_subrc                    = lv_subrc
        e_msgid                    = lv_msgid
        e_msgno                    = lv_msgno
        e_msgty                    = lv_msgty
        e_msgv1                    = lv_msgv1
        e_msgv2                    = lv_msgv2
        e_msgv3                    = lv_msgv3
        e_msgv4                    = lv_msgv4
      TABLES
        t_blntab                   = lt_blntab
        t_ftclear                  = lt_ftclear
        t_ftpost                   = lt_ftpost
        t_fttax                    = lt_fttax
      EXCEPTIONS
        clearing_procedure_invalid = 1
        table_t041a_empty          = 2
        transaction_code_invalid   = 3
        amount_format_error        = 4
        too_many_line_items        = 5
        company_code_invalid       = 6
        screen_not_found           = 7
        no_authorization           = 8
        OTHERS                     = 9.
    IF sy-subrc <> 0.
      lv_subrc = sy-subrc.
    ENDIF.

    CALL FUNCTION 'ZPOSTING_INTERFACE_END'
      EXCEPTIONS
        session_not_processable = 1
        OTHERS                  = 2.
    DATA(lv_end_subrc) = sy-subrc.

    IF lv_msgid IS NOT INITIAL AND lv_msgno IS NOT INITIAL.
      CALL FUNCTION 'BAPI_MESSAGE_GETDETAIL'
        EXPORTING
          id         = lv_msgid
          number     = lv_msgno
          language   = sy-langu
          textformat = lv_textformat
          message_v1 = lv_msgv1
          message_v2 = lv_msgv2
          message_v3 = lv_msgv3
          message_v4 = lv_msgv4
        IMPORTING
          message    = lv_message.
    ENDIF.

    "a BDC session that refused to close leaves the posting state uncertain
    IF lv_end_subrc <> 0.
      lv_message = |{ lv_message } (posting interface end subrc { lv_end_subrc })| ##NO_TEXT.
    ENDIF.

    READ TABLE lt_blntab INTO DATA(lw_blntab) INDEX 1.
    IF sy-subrc <> 0 OR lv_subrc <> 0.
      cw_claim-status  = icon_led_red.
      cw_claim-message = COND #( WHEN lv_message IS NOT INITIAL
                                 THEN lv_message
                                 ELSE |Clearing failed, subrc { lv_subrc }| ) ##NO_TEXT.
      RETURN.
    ENDIF.

    cw_claim-augbl   = lw_blntab-belnr.
    cw_claim-sel     = abap_false.
    cw_claim-message = lv_message.
    cw_claim-style   = lcl_util=>disable_cells(
                         VALUE #( ( `SEL` ) ( `BELNR_OUTS` ) ( `GJAHR_OUTS` ) ) ).
  ENDMETHOD.

  METHOD add_ftpost.
    ct_ftpost = VALUE #( BASE ct_ftpost ( stype = iv_stype
                                          count = iv_count
                                          fnam  = iv_fnam
                                          fval  = iv_fval ) ).
  ENDMETHOD.
ENDCLASS.

CLASS lcl_app IMPLEMENTATION.
  METHOD get_mode.
    rv_mode = COND #( WHEN p_mode_a = abap_true THEN gc_mode_a ELSE gc_mode_b ).
  ENDMETHOD.

  METHOD initialize.
    lcl_config=>load( ).

    s_bsart[] = lcl_config=>doc_type_po( ).

    gv_doc_type_ar = lcl_config=>doc_type_ar( ).
  ENDMETHOD.

  METHOD modify_screen.
    DATA(lv_mode) = get_mode( ).

    LOOP AT SCREEN.
      CASE screen-group1.
        WHEN 'MA'.
          screen-active = COND #( WHEN lv_mode = gc_mode_a THEN 1 ELSE 0 ).
        WHEN 'MB'.
          screen-active = COND #( WHEN lv_mode = gc_mode_b THEN 1 ELSE 0 ).
        WHEN OTHERS.
          "no visibility change
      ENDCASE.

      IF screen-name CS 'P_KUNNR'.
        screen-required = '2'.
      ENDIF.

      MODIFY SCREEN.
    ENDLOOP.
  ENDMETHOD.

  METHOD validate_screen.
    SELECT SINGLE bukrs
      FROM t001
      WHERE bukrs IN @s_bukrs
      INTO @gv_bukrs.
    IF sy-subrc <> 0.
      MESSAGE s398(00) WITH 'Company code does not exist:' s_bukrs-low DISPLAY LIKE 'E' ##NO_TEXT.
    ENDIF.

    IF get_mode( ) = gc_mode_a.
      IF p_budat IS INITIAL.
        MESSAGE e398(00) WITH 'Posting date is mandatory' ##NO_TEXT.
      ENDIF.
      check_period( EXPORTING iv_bukrs = gv_bukrs
                              iv_budat = p_budat ).

      IF p_kunnr IS INITIAL .
        MESSAGE s398(00) WITH 'Claimable AR customer is mandatory' DISPLAY LIKE 'E' ##NO_TEXT.
      ENDIF.

      RETURN.
    ENDIF.

    IF p_clrdt IS INITIAL.
      MESSAGE s398(00) WITH 'Clearing posting date is mandatory' DISPLAY LIKE 'E' ##NO_TEXT.
    ENDIF.

    check_period( EXPORTING iv_bukrs = gv_bukrs
                            iv_budat = p_clrdt ).
  ENDMETHOD.

  METHOD check_period.
    CALL FUNCTION 'FI_PERIOD_CHECK'
      EXPORTING
        i_bukrs            = iv_bukrs
        i_gjahr            = iv_budat(4)
        i_koart            = '+'
        i_monat            = CONV frper( iv_budat+4(2) )
      EXCEPTIONS
        error_period       = 1
        error_period_accnt = 2
        invalid_input      = 3
        OTHERS             = 4.
    IF sy-subrc <> 0.
      MESSAGE e398(00) WITH 'Posting period is not open:' iv_budat ##NO_TEXT.
    ENDIF.
  ENDMETHOD.

  METHOD run.
    IF get_mode( ) = gc_mode_a.
      go_processor = NEW lcl_mode_a( ).
    ELSE.
      go_processor = NEW lcl_mode_b( ).
    ENDIF.

    go_processor->select( ).
  ENDMETHOD.

  METHOD show.
    IF go_processor IS NOT BOUND OR go_processor->has_data( ) = abap_false.
      RETURN.
    ENDIF.

    go_processor->display( ).
  ENDMETHOD.
ENDCLASS.

*---------------------------------------------------------------------*
* Event blocks
*---------------------------------------------------------------------*
INITIALIZATION.
  lcl_app=>initialize( ).

AT SELECTION-SCREEN OUTPUT.
  lcl_app=>modify_screen( ).

AT SELECTION-SCREEN.
  lcl_app=>validate_screen( ).

START-OF-SELECTION.
  lcl_app=>run( ).

END-OF-SELECTION.
  lcl_app=>show( ).

FORM f4callback TABLES record_tab STRUCTURE seahlpres
                CHANGING shlp TYPE shlp_descr
                         callcontrol LIKE ddshf4ctrl.
  " Set dialog type to 'C' (Dialog with value restriction)
  shlp-intdescr-dialogtype = 'C'.
  callcontrol-no_maxdisp = space.
  callcontrol-maxrecords = 500.
ENDFORM.
